# =============================================================================
# Lambda: DynamoDB Stream Trigger — Starts Step Functions for MEMBER# changes
# Filters stream records for MEMBER# INSERT/MODIFY, deduplicates memberIds,
# and starts one Step Functions execution per unique member.
# =============================================================================

locals {
  step_function_arn = var.step_function_arn != "" ? var.step_function_arn : "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project_name}-orchestration-${var.environment}"
}

# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "lambda_trigger" {
  name              = "/aws/lambda/${var.project_name}-stream-trigger-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-stream-trigger-logs"
  }
}

# --- Lambda Function ---
resource "aws_lambda_function" "stream_trigger" {
  function_name = "${var.project_name}-stream-trigger-${var.environment}"
  description   = "DynamoDB Stream trigger: starts Step Functions for MEMBER# changes"
  role          = aws_iam_role.lambda_trigger_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.lambda_trigger.output_path
  source_code_hash = data.archive_file.lambda_trigger.output_base64sha256

  environment {
    variables = {
      SFN_STATE_MACHINE_ARN = local.step_function_arn
    }
  }

  tags = {
    Name = "${var.project_name}-stream-trigger"
    Role = "DynamoDB Stream to Step Functions Trigger"
  }

  depends_on = [aws_cloudwatch_log_group.lambda_trigger]
}

# --- Lambda Code ---
data "archive_file" "lambda_trigger" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-stream-trigger.zip"

  source {
    content  = <<-PYTHON
import json
import os
import re
import logging
import boto3
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sfn_client = boto3.client("stepfunctions")
STATE_MACHINE_ARN = os.environ["SFN_STATE_MACHINE_ARN"]


def lambda_handler(event, context):
    """
    Process DynamoDB Stream batch, filter MEMBER# changes, start Step Functions.
    Returns batchItemFailures for partial batch failure reporting.
    """
    records = event.get("Records", [])
    if not records:
        return {"batchItemFailures": []}

    # Phase 1: Filter and deduplicate
    member_ids_to_process = set()
    record_sequence_map = {}  # memberId -> earliest sequence number

    for record in records:
        event_name = record.get("eventName", "")

        # Skip REMOVE events — member deletion does not trigger re-analysis
        if event_name == "REMOVE":
            continue

        # Only process INSERT and MODIFY
        if event_name not in ("INSERT", "MODIFY"):
            continue

        keys = record.get("dynamodb", {}).get("Keys", {})
        record_type = keys.get("recordType", {}).get("S", "")
        member_id = keys.get("memberId", {}).get("S", "")
        sequence_number = record.get("dynamodb", {}).get("SequenceNumber", "")

        # Only trigger on MEMBER# record changes
        if record_type.startswith("MEMBER#"):
            member_ids_to_process.add(member_id)
            if member_id not in record_sequence_map:
                record_sequence_map[member_id] = sequence_number

    logger.info("Found %d unique members to re-analyze from %d stream records",
                len(member_ids_to_process), len(records))

    if not member_ids_to_process:
        return {"batchItemFailures": []}

    # Phase 2: Start executions
    failures = []
    # Use hour-based window for execution name — prevents duplicate runs within the same hour
    time_window = datetime.utcnow().strftime("%Y%m%d-%H")

    for member_id in member_ids_to_process:
        try:
            # Execution name uses member + hour window — same member in same hour = rejected as duplicate
            execution_name = f"auto-{member_id}-{time_window}"
            execution_name = re.sub(r"[^a-zA-Z0-9_-]", "_", execution_name)

            sfn_client.start_execution(
                stateMachineArn=STATE_MACHINE_ARN,
                name=execution_name,
                input=json.dumps({
                    "memberId": member_id,
                    "forceReanalyze": True,
                    "userMessage": "Auto-analysis triggered by data update",
                    "sessionId": f"auto-{int(datetime.utcnow().timestamp())}"
                })
            )
            logger.info("Started execution for %s: %s", member_id, execution_name)

        except sfn_client.exceptions.ExecutionAlreadyExists:
            # Treat as success — member is already being re-analyzed
            logger.warning("Execution already running for %s, skipping", member_id)

        except Exception as e:
            logger.error("Failed to start execution for %s: %s", member_id, str(e))
            failures.append({
                "itemIdentifier": record_sequence_map[member_id]
            })

    return {"batchItemFailures": failures}
PYTHON
    filename = "handler.py"
  }
}

# --- Event Source Mapping: DynamoDB Stream → Lambda ---
resource "aws_lambda_event_source_mapping" "stream_trigger" {
  event_source_arn  = aws_dynamodb_table.unified_member_profile.stream_arn
  function_name     = aws_lambda_function.stream_trigger.arn
  starting_position = "LATEST"
  batch_size        = 100

  maximum_batching_window_in_seconds = 30

  function_response_types = ["ReportBatchItemFailures"]

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
      })
    }
  }

  depends_on = [aws_iam_role_policy.lambda_trigger_streams]
}
