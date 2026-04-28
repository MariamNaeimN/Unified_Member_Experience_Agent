# =============================================================================
# Lambda: Write Results — Step 3 of orchestration
# Writes AI Decision, Care Gaps, Interventions, and Summary back to DynamoDB
# =============================================================================

resource "aws_cloudwatch_log_group" "write_results" {
  name              = "/aws/lambda/${var.project_name}-write-results-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "write_results" {
  function_name = "${var.project_name}-write-results-${var.environment}"
  description   = "Step 3: Write AI results (decisions, gaps, interventions, summary) back to DynamoDB"
  role          = aws_iam_role.lambda_orch_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  filename         = data.archive_file.write_results.output_path
  source_code_hash = data.archive_file.write_results.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME       = var.dynamodb_agent_table_name
      DYNAMODB_SOURCE_TABLE     = var.dynamodb_table_name
      ENVIRONMENT               = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-write-results"
    Role = "Step 3 - Write AI Results to DynamoDB"
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.write_results]
}

data "archive_file" "write_results" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-write-results.zip"

  source {
    content  = <<-PYTHON
import json
import os
import logging
import boto3
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]


def lambda_handler(event, context):
    """
    Write AI analysis results as a single SESSION record to DynamoDB.
    Input:  { "memberId": "M-10042", "profile": {...}, "aiResult": {...}, "sessionId": "...", "userMessage": "..." }
    Output: { "memberId": "M-10042", "decisionId": "...", "sessionId": "...", "careGaps": N, "interventions": N, "agentResponse": "...", "status": "success" }
    """
    member_id = event.get("memberId")
    ai_result = event.get("aiResult")

    if not ai_result:
        return {
            "memberId": member_id,
            "recordsWritten": 0,
            "status": "skipped",
            "reason": "No AI result to write"
        }

    table = dynamodb.Table(TABLE_NAME)
    now = datetime.utcnow().isoformat()

    session_id = event.get("sessionId", "session-" + str(int(datetime.utcnow().timestamp())))
    user_message = event.get("userMessage", "Analyze member " + member_id)
    decision_id = ai_result.get("decisionId", f"D-{int(datetime.utcnow().timestamp())}")
    agent_response = build_chat_response(ai_result)
    expires_at = int((datetime.utcnow() + timedelta(hours=24)).timestamp())

    # Build single session record with all details nested
    session_record = {
        "memberId": member_id,
        "recordType": f"SESSION#{session_id}",
        "sessionId": session_id,
        "decisionId": decision_id,
        "gsiRecordType": "SESSION",
        "updatedAt": now,
        "expiresAt": expires_at,
        # Chat
        "userMessage": user_message,
        "agentResponse": agent_response,
        # AI Decision
        "analysis": ai_result.get("analysis", ""),
        "riskAssessment": ai_result.get("riskAssessment", ""),
        "claimsInsight": ai_result.get("claimsInsight", ""),
        "careHistoryInsight": ai_result.get("careHistoryInsight", ""),
        "medicationInsight": ai_result.get("medicationInsight", ""),
        "confidence": str(ai_result.get("confidence", 0)),
        "model": ai_result.get("model", ""),
        # Summary
        "talkingPoints": ai_result.get("talkingPoints", []),
        # Care Gaps (nested list)
        "careGaps": [
            {
                "gapId": f"GAP-{int(datetime.utcnow().timestamp())}-{i}",
                "type": g.get("type", ""),
                "priority": g.get("priority", ""),
                "protocol": g.get("protocol", ""),
                "dueWithin": g.get("dueWithin", ""),
                "status": "Open"
            }
            for i, g in enumerate(ai_result.get("careGaps", []))
        ],
        # Interventions (nested list)
        "interventions": [
            {
                "interventionId": f"INT-{int(datetime.utcnow().timestamp())}-{i}",
                "type": inv.get("type", ""),
                "target": inv.get("target", ""),
                "message": inv.get("message", ""),
                "linkedGap": inv.get("linkedGap", ""),
                "system": inv.get("system", ""),
                "status": "Triggered"
            }
            for i, inv in enumerate(ai_result.get("recommendedInterventions", []))
        ],
        # Notifications (nested list for UI)
        "notifications": [
            {
                "type": inv.get("type", ""),
                "target": inv.get("target", ""),
                "title": f"[{inv.get('type', '')}] {inv.get('linkedGap', '')}",
                "message": inv.get("message", ""),
                "priority": inv.get("priority", "MEDIUM"),
                "status": "unread"
            }
            for inv in ai_result.get("recommendedInterventions", [])
        ]
    }

    # Remove empty strings (DynamoDB doesn't allow them)
    clean_record = {k: v for k, v in session_record.items() if v != "" and v is not None}
    table.put_item(Item=clean_record)

    logger.info(f"Wrote SESSION#{session_id} for {member_id} "
                f"({len(ai_result.get('careGaps', []))} gaps, "
                f"{len(ai_result.get('recommendedInterventions', []))} interventions)")

    return {
        "memberId": member_id,
        "decisionId": decision_id,
        "sessionId": session_id,
        "recordsWritten": 1,
        "careGaps": len(ai_result.get("careGaps", [])),
        "interventions": len(ai_result.get("recommendedInterventions", [])),
        "agentResponse": agent_response,
        "status": "success"
    }


def build_chat_response(ai_result):
    """Build a conversational response from the structured AI result."""
    parts = []

    analysis = ai_result.get("analysis", "")
    if analysis:
        parts.append(analysis)

    risk = ai_result.get("riskAssessment", "")
    if risk:
        parts.append("\nRisk Assessment: " + risk)

    claims_insight = ai_result.get("claimsInsight", "")
    if claims_insight:
        parts.append("\nClaims Pattern: " + claims_insight)

    care_insight = ai_result.get("careHistoryInsight", "")
    if care_insight:
        parts.append("Care Engagement: " + care_insight)

    med_insight = ai_result.get("medicationInsight", "")
    if med_insight:
        parts.append("Medication Status: " + med_insight)

    gaps = ai_result.get("careGaps", [])
    if gaps:
        parts.append("\nCare Gaps Identified:")
        for g in gaps:
            priority = g.get("priority", "")
            icon = "!!" if priority in ("CRITICAL", "HIGH") else "-"
            parts.append(f"  {icon} {g.get('type', '')} (Priority: {priority}, Due: {g.get('dueWithin', '')})")

    interventions = ai_result.get("recommendedInterventions", [])
    if interventions:
        parts.append("\nActions Triggered:")
        for inv in interventions:
            parts.append(f"  [{inv.get('type', '')}] {inv.get('message', '')}")

    points = ai_result.get("talkingPoints", [])
    if points:
        parts.append("\nTalking Points for Your Call:")
        for i, p in enumerate(points, 1):
            parts.append(f"  {i}. {p}")

    return "\n".join(parts)
PYTHON
    filename = "handler.py"
  }
}
