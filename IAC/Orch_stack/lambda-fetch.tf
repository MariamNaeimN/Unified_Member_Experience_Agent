# =============================================================================
# Lambda: Fetch Profile — Step 1 of orchestration
# Queries DynamoDB for ALL records of a member and assembles unified profile
# =============================================================================

resource "aws_cloudwatch_log_group" "fetch_profile" {
  name              = "/aws/lambda/${var.project_name}-fetch-profile-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "fetch_profile" {
  function_name = "${var.project_name}-fetch-profile-${var.environment}"
  description   = "Step 1: Fetch all member data from DynamoDB and assemble unified profile"
  role          = aws_iam_role.lambda_orch_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  filename         = data.archive_file.fetch_profile.output_path
  source_code_hash = data.archive_file.fetch_profile.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME       = var.dynamodb_table_name
      DYNAMODB_AGENT_TABLE_NAME = var.dynamodb_agent_table_name
      ENVIRONMENT               = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-fetch-profile"
    Role = "Step 1 - Fetch Member Profile"
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.fetch_profile]
}

data "archive_file" "fetch_profile" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-fetch-profile.zip"

  source {
    content  = <<-PYTHON
import json
import os
import logging
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
AGENT_TABLE_NAME = os.environ.get("DYNAMODB_AGENT_TABLE_NAME", TABLE_NAME)

CACHE_TTL_HOURS = 1

# Source data types — these are the records that come from S3 ETL
SOURCE_TYPES = ("MEMBER#", "PATIENT#", "CONDITION#", "CLAIM#", "PHARMACY#", "CARE_EVENT#", "PROVIDER#")
# AI-generated types — these are written by the orchestration workflow
AI_TYPES = ("SESSION#",)


def lambda_handler(event, context):
    """
    Fetch all records for a member from DynamoDB.
    Detects if source data changed since last AI analysis.

    Input:  { "memberId": "M-10042", "forceReanalyze": false, "userMessage": "Tell me about M-10042", "sessionId": "session-xxx" }
    Output: {
        "memberId": "M-10042",
        "profile": {...},
        "needsReanalysis": true/false,
        "cachedResult": {...} or null,
        "chatHistory": [...],
        "userMessage": "...",
        "sessionId": "..."
    }
    """
    member_id = event.get("memberId")
    force = event.get("forceReanalyze", False)
    user_message = event.get("userMessage", "Analyze member " + str(event.get("memberId", "")))
    session_id = event.get("sessionId", "session-" + str(int(datetime.utcnow().timestamp())))

    if not member_id:
        raise ValueError("memberId is required")

    table = dynamodb.Table(TABLE_NAME)
    logger.info(f"Fetching profile for {member_id} (force={force})")

    # Query source data from the main table
    response = table.query(
        KeyConditionExpression=Key("memberId").eq(member_id)
    )

    items = response.get("Items", [])
    logger.info(f"Found {len(items)} source records for {member_id}")

    # Query agent output from the agent table
    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    agent_response = agent_table.query(
        KeyConditionExpression=Key("memberId").eq(member_id)
    )
    agent_items = agent_response.get("Items", [])
    logger.info(f"Found {len(agent_items)} agent records for {member_id}")

    all_items = items + agent_items

    if not items:
        return {
            "memberId": member_id,
            "profile": None,
            "needsReanalysis": False,
            "cachedResult": None,
            "error": f"No records found for {member_id}"
        }

    # Organize by record type
    profile = {
        "member": None,
        "patient": None,
        "conditions": [],
        "claims": [],
        "pharmacy": [],
        "careEvents": [],
        "careGaps": [],
        "carePlans": [],
        "providers": []
    }

    # Track AI results separately
    latest_session = None
    chat_history = []

    # Track latest updatedAt for source data vs AI data
    latest_source_update = ""
    latest_ai_update = ""

    for item in all_items:
        record_type = item.get("recordType", "")
        updated_at = item.get("updatedAt", "")

        # Categorize and track timestamps
        if any(record_type.startswith(t) for t in SOURCE_TYPES):
            if updated_at > latest_source_update:
                latest_source_update = updated_at

        if any(record_type.startswith(t) for t in AI_TYPES):
            if updated_at > latest_ai_update:
                latest_ai_update = updated_at

        # Organize into profile
        if record_type.startswith("MEMBER#"):
            profile["member"] = item
        elif record_type.startswith("PATIENT#"):
            profile["patient"] = item
        elif record_type.startswith("CONDITION#"):
            profile["conditions"].append(item)
        elif record_type.startswith("CLAIM#"):
            profile["claims"].append(item)
        elif record_type.startswith("PHARMACY#"):
            profile["pharmacy"].append(item)
        elif record_type.startswith("CARE_EVENT#"):
            profile["careEvents"].append(item)
        elif record_type.startswith("PROVIDER#"):
            profile["providers"].append(item)
        elif record_type.startswith("SESSION#"):
            if not latest_session or updated_at > latest_session.get("updatedAt", ""):
                latest_session = item
            chat_history.append(item)

    # Determine if reanalysis is needed
    has_ai_results = latest_session is not None
    source_changed = latest_source_update > latest_ai_update if has_ai_results else True

    # Check if cached results are older than 1 hour
    cache_expired = False
    if has_ai_results and latest_ai_update:
        try:
            ai_time = datetime.fromisoformat(latest_ai_update)
            cache_expired = (datetime.utcnow() - ai_time) > timedelta(hours=CACHE_TTL_HOURS)
        except (ValueError, TypeError):
            cache_expired = True

    needs_reanalysis = force or not has_ai_results or source_changed or cache_expired

    if needs_reanalysis:
        if force:
            reason = "forced"
        elif not has_ai_results:
            reason = "no prior analysis"
        elif cache_expired:
            reason = f"cache expired (>{CACHE_TTL_HOURS}h)"
        else:
            reason = "source data updated since last analysis"
        logger.info(f"Reanalysis needed: {reason} (source={latest_source_update}, ai={latest_ai_update})")
    else:
        logger.info(f"Cached AI results are current (source={latest_source_update}, ai={latest_ai_update})")

    # Build cached result from latest session
    cached_result = None
    if not needs_reanalysis and latest_session:
        cached_result = {
            "memberId": member_id,
            "decisionId": latest_session.get("decisionId", ""),
            "analysis": latest_session.get("analysis", ""),
            "riskAssessment": latest_session.get("riskAssessment", ""),
            "confidence": latest_session.get("confidence", ""),
            "careGaps": len(latest_session.get("careGaps", [])),
            "interventions": len(latest_session.get("interventions", [])),
            "summary": latest_session.get("agentResponse", ""),
            "talkingPoints": latest_session.get("talkingPoints", []),
            "status": "cached"
        }

    # Convert Decimal types for JSON serialization
    profile = json.loads(json.dumps(profile, default=str))

    logger.info(f"Profile assembled: {len(profile['conditions'])} conditions, "
                f"{len(profile['claims'])} claims, {len(profile['pharmacy'])} pharmacy, "
                f"{len(profile['careEvents'])} events | needsReanalysis={needs_reanalysis}")

    return {
        "memberId": member_id,
        "profile": profile,
        "needsReanalysis": needs_reanalysis,
        "cachedResult": cached_result,
        "chatHistory": sorted(
            [json.loads(json.dumps(ch, default=str)) for ch in chat_history],
            key=lambda x: x.get("updatedAt", "")
        )[-10:],
        "userMessage": user_message,
        "sessionId": session_id,
        "error": None
    }
PYTHON
    filename = "handler.py"
  }
}
