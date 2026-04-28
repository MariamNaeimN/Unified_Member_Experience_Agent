# =============================================================================
# Lambda ETL — Transforms raw S3 files into DynamoDB records
# Matches: project_Flow/MOCK-DATA.md → Lambda ETL Processing Flow
#
# Trigger: S3 ObjectCreated events on raw/ prefix
# Process: Read → Parse → Transform → Validate → Write to DynamoDB → Archive
# =============================================================================

# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "lambda_etl" {
  name              = "/aws/lambda/${var.project_name}-etl-processor-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-etl-logs"
  }
}

# --- Lambda Function ---
resource "aws_lambda_function" "etl_processor" {
  function_name = "${var.project_name}-etl-processor-${var.environment}"
  description   = "ETL processor: transforms raw S3 healthcare data into DynamoDB unified profile records"
  role          = aws_iam_role.lambda_etl_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  # Placeholder — replace with actual deployment package
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.unified_member_profile.name
      S3_BUCKET_NAME      = aws_s3_bucket.data_lake.id
      PROCESSED_PREFIX    = "processed/"
      ENVIRONMENT         = var.environment
      LOG_LEVEL           = var.environment == "prod" ? "WARNING" : "INFO"
    }
  }

  tags = {
    Name = "${var.project_name}-etl-processor"
    Role = "S3 Raw Data to DynamoDB ETL"
  }

  depends_on = [
    aws_iam_role_policy.lambda_logging,
    aws_cloudwatch_log_group.lambda_etl
  ]
}

# --- Placeholder Lambda code (minimal handler) ---
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-etl-placeholder.zip"

  source {
    content  = <<-PYTHON
import json
import os
import csv
import io
import logging
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
BUCKET_NAME = os.environ["S3_BUCKET_NAME"]
PROCESSED_PREFIX = os.environ.get("PROCESSED_PREFIX", "processed/")


def lambda_handler(event, context):
    """
    ETL Pipeline:
    1. Triggered by S3 ObjectCreated event
    2. Reads raw file from S3
    3. Detects data type from prefix (members, claims, pharmacy, care-events, providers)
    4. Parses and transforms records
    5. Batch writes to DynamoDB using single-table design
    6. Archives processed file
    """
    table = dynamodb.Table(TABLE_NAME)

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        logger.info(f"Processing: s3://{bucket}/{key}")

        # Determine data type from S3 prefix
        data_type = detect_data_type(key)
        if not data_type:
            logger.warning(f"Unknown data type for key: {key}")
            continue

        # Read file from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response["Body"].read().decode("utf-8")

        # Parse based on format
        if key.endswith(".csv"):
            records = parse_csv(content)
        elif key.endswith(".json"):
            records = json.loads(content)
            if isinstance(records, dict):
                records = [records]
        else:
            logger.warning(f"Unsupported file format: {key}")
            continue

        # Transform and write to DynamoDB
        transformed = transform_records(records, data_type)
        batch_write(table, transformed)

        # Sync: delete stale records no longer in the source file
        # For MEMBER type, we produce both MEMBER and PATIENT records
        new_keys = {(item["memberId"], item["recordType"]) for item in transformed}
        if data_type == "MEMBER":
            deleted_count = delete_stale_records(table, "MEMBER", new_keys)
            deleted_count += delete_stale_records(table, "PATIENT", new_keys)
        else:
            deleted_count = delete_stale_records(table, data_type, new_keys)
        if deleted_count > 0:
            logger.info(f"Deleted {deleted_count} stale {data_type} records from DynamoDB")

        # Archive processed file
        archive_key = key.replace("raw/", PROCESSED_PREFIX, 1)
        s3.copy_object(
            Bucket=bucket,
            CopySource={"Bucket": bucket, "Key": key},
            Key=archive_key,
        )
        logger.info(f"Archived to: s3://{bucket}/{archive_key}")

        logger.info(f"Processed {len(transformed)} records ({deleted_count} stale deleted) from {key}")

    return {"statusCode": 200, "body": f"ETL complete"}


def detect_data_type(key):
    """Detect data type from S3 key prefix."""
    prefix_map = {
        "raw/members/": "MEMBER",
        "raw/claims/": "CLAIM",
        "raw/pharmacy/": "PHARMACY",
        "raw/care-events/": "CARE_EVENT",
        "raw/providers/": "PROVIDER",
        "raw/conditions/": "CONDITION",
    }
    for prefix, dtype in prefix_map.items():
        if key.startswith(prefix):
            return dtype
    return None


def parse_csv(content):
    """Parse CSV content into list of dicts."""
    reader = csv.DictReader(io.StringIO(content))
    return list(reader)


def transform_records(records, data_type):
    """Transform raw records into DynamoDB single-table format."""
    transformed = []

    for record in records:
        if data_type == "MEMBER":
            member_id = record.get("memberId", "")
            # --- MEMBER record (payer side) ---
            member_item = {
                "memberId": member_id,
                "recordType": f"MEMBER#{member_id}",
                "firstName": record.get("firstName", ""),
                "lastName": record.get("lastName", ""),
                "dob": record.get("dob", ""),
                "gender": record.get("gender", ""),
                "planName": record.get("planName", ""),
                "planType": record.get("planType", ""),
                "coverageStatus": record.get("coverageStatus", ""),
                "enrollmentDate": record.get("enrollmentDate", ""),
                "state": record.get("state", ""),
                "gsiRecordType": "MEMBER",
                "updatedAt": datetime.utcnow().isoformat(),
            }
            transformed.append(member_item)

            # --- PATIENT record (clinical side) ---
            allergies_raw = record.get("allergies", "None")
            allergies_list = [] if allergies_raw == "None" else allergies_raw.split(";")
            patient_item = {
                "memberId": member_id,
                "recordType": f"PATIENT#{member_id}",
                "pcpId": record.get("pcpId", ""),
                "livingSituation": record.get("livingSituation", ""),
                "riskScore": record.get("riskScore", "0"),
                "allergies": allergies_list,
                "bloodType": record.get("bloodType", ""),
                "bmi": record.get("bmi", ""),
                "smokingStatus": record.get("smokingStatus", ""),
                "preferredLanguage": record.get("preferredLanguage", ""),
                "gsiRecordType": "PATIENT",
                "updatedAt": datetime.utcnow().isoformat(),
            }
            transformed.append(patient_item)
            continue

        elif data_type == "CLAIM":
            item = {
                "memberId": record.get("memberId", ""),
                "recordType": f"CLAIM#{record.get('claimId', '')}",
                "claimId": record.get("claimId", ""),
                "claimType": record.get("claimType", ""),
                "diagnosisCode": record.get("diagnosisCode", ""),
                "diagnosisDesc": record.get("diagnosisDesc", ""),
                "providerId": record.get("providerId", ""),
                "facilityName": record.get("facilityName", ""),
                "serviceDate": record.get("serviceDate", ""),
                "paidAmount": record.get("paidAmount", ""),
                "status": record.get("status", ""),
                "gsiRecordType": "CLAIM",
                "updatedAt": datetime.utcnow().isoformat(),
            }

        elif data_type == "PHARMACY":
            item = {
                "memberId": record.get("memberId", ""),
                "recordType": f"PHARMACY#{record.get('rxId', '')}",
                "rxId": record.get("rxId", ""),
                "medication": record.get("medication", ""),
                "dosage": record.get("dosage", ""),
                "prescriberId": record.get("prescriberId", ""),
                "pharmacyName": record.get("pharmacyName", ""),
                "lastRefillDate": record.get("lastRefillDate", ""),
                "daysSupply": record.get("daysSupply", 0),
                "refillsRemaining": record.get("refillsRemaining", 0),
                "adherencePercent": record.get("adherencePercent", 0),
                "status": record.get("status", ""),
                "gsiRecordType": "PHARMACY",
                "updatedAt": datetime.utcnow().isoformat(),
            }

        elif data_type == "CARE_EVENT":
            item = {
                "memberId": record.get("memberId", ""),
                "recordType": f"CARE_EVENT#{record.get('eventId', '')}",
                "eventId": record.get("eventId", ""),
                "eventType": record.get("eventType", ""),
                "providerId": record.get("providerId", ""),
                "facilityName": record.get("facilityName", ""),
                "date": record.get("date", ""),
                "diagnosisCode": record.get("diagnosisCode", ""),
                "outcome": record.get("outcome", ""),
                "notes": record.get("notes", ""),
                "gsiRecordType": "CARE_EVENT",
                "updatedAt": datetime.utcnow().isoformat(),
            }

        elif data_type == "PROVIDER":
            member_id = record.get("memberId", "")
            provider_id = record.get("providerId", "")
            item = {
                "memberId": member_id,
                "recordType": f"PROVIDER#{provider_id}",
                "providerId": provider_id,
                "relationship": record.get("relationship", ""),
                "name": record.get("name", ""),
                "specialty": record.get("specialty", ""),
                "facilityName": record.get("facilityName", ""),
                "npi": record.get("npi", ""),
                "phone": record.get("phone", ""),
                "state": record.get("state", ""),
                "inNetwork": record.get("inNetwork", ""),
                "gsiRecordType": "PROVIDER",
                "updatedAt": datetime.utcnow().isoformat(),
            }

        elif data_type == "CONDITION":
            item = {
                "memberId": record.get("memberId", ""),
                "recordType": f"CONDITION#{record.get('conditionId', '')}",
                "conditionId": record.get("conditionId", ""),
                "diagnosis": record.get("diagnosis", ""),
                "icdCode": record.get("icdCode", ""),
                "onsetDate": record.get("onsetDate", ""),
                "status": record.get("status", ""),
                "severity": record.get("severity", ""),
                "lastAssessedDate": record.get("lastAssessedDate", ""),
                "gsiRecordType": "CONDITION",
                "updatedAt": datetime.utcnow().isoformat(),
            }
        else:
            continue

        transformed.append(item)

    return transformed


def batch_write(table, items):
    """Batch write items to DynamoDB (25 items per batch)."""
    with table.batch_writer() as batch:
        for item in items:
            # Remove empty strings (DynamoDB doesn't allow them)
            clean_item = {k: v for k, v in item.items() if v != "" and v is not None}
            batch.put_item(Item=clean_item)


def delete_stale_records(table, data_type, new_keys):
    """
    Sync DynamoDB with S3 source file by deleting records that no longer exist.

    1. Query DynamoDB GSI for all records of this data_type
    2. Compare against the new_keys set from the uploaded file
    3. Delete any records in DynamoDB that are NOT in the new file

    This ensures DynamoDB is an exact mirror of the S3 source files.
    """
    deleted_count = 0

    # Query all existing records of this type using the GSI
    existing_keys = set()
    query_params = {
        "IndexName": "recordType-index",
        "KeyConditionExpression": Key("gsiRecordType").eq(data_type),
        "ProjectionExpression": "memberId, recordType",
    }

    # Handle pagination for large datasets
    while True:
        response = table.query(**query_params)
        for item in response.get("Items", []):
            existing_keys.add((item["memberId"], item["recordType"]))

        # Check for more pages
        if "LastEvaluatedKey" in response:
            query_params["ExclusiveStartKey"] = response["LastEvaluatedKey"]
        else:
            break

    # Find stale keys: exist in DynamoDB but NOT in the new file
    stale_keys = existing_keys - new_keys

    if not stale_keys:
        logger.info(f"No stale {data_type} records to delete")
        return 0

    logger.info(f"Found {len(stale_keys)} stale {data_type} records to delete")

    # Batch delete stale records
    with table.batch_writer() as batch:
        for member_id, record_type in stale_keys:
            batch.delete_item(
                Key={"memberId": member_id, "recordType": record_type}
            )
            deleted_count += 1

    return deleted_count
PYTHON
    filename = "handler.py"
  }
}

# --- Permission for S3 to invoke Lambda ---
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_lake.arn
  source_account = data.aws_caller_identity.current.account_id
}
