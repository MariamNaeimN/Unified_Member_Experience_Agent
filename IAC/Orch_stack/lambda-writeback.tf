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
from boto3.dynamodb.conditions import Key
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]


def lambda_handler(event, context):
    """
    Write AI analysis results to DynamoDB with structured output records.
    Deletes old analysis records, writes new structured records, then writes SESSION.
    Input:  { "memberId": "M-10042", "profile": {...}, "aiResult": {...}, "sessionId": "...", "userMessage": "..." }
    Output: { "memberId": "M-10042", "decisionId": "...", "sessionId": "...", "recordsWritten": N, ... }
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
    session_id = event.get("sessionId", "session-" + str(int(datetime.utcnow().timestamp())))
    user_message = event.get("userMessage", "Analyze member " + member_id)

    # Phase 1: Delete old analysis records (preserves SESSION# records)
    deleted_count = delete_old_analysis_records(table, member_id)

    # Phase 2: Write new structured records
    result = write_structured_records(table, member_id, ai_result, session_id, user_message)
    result["recordsDeleted"] = deleted_count

    return result


def delete_old_analysis_records(table, member_id):
    """
    Delete all existing AI analysis records for a member before writing new ones.
    Deletes AI_DECISION#, CARE_GAP#, INTERVENTION#, SUMMARY# records.
    Does NOT delete SESSION# records (chat history is preserved).
    Returns the count of deleted records.
    """
    prefixes_to_delete = ["AI_DECISION#", "CARE_GAP#", "INTERVENTION#", "SUMMARY#"]
    deleted_count = 0

    for prefix in prefixes_to_delete:
        response = table.query(
            KeyConditionExpression=Key("memberId").eq(member_id) & Key("recordType").begins_with(prefix)
        )
        old_records = response.get("Items", [])

        if old_records:
            with table.batch_writer() as batch:
                for record in old_records:
                    batch.delete_item(Key={
                        "memberId": record["memberId"],
                        "recordType": record["recordType"]
                    })
                    deleted_count += 1

    if deleted_count > 0:
        logger.info("Deleted %d old analysis records for %s", deleted_count, member_id)

    return deleted_count


def write_structured_records(table, member_id, ai_result, session_id, user_message):
    """
    Write AI_DECISION#, CARE_GAP#, INTERVENTION#, SUMMARY#, and SESSION# records.
    Returns metadata about what was written.
    """
    now = datetime.utcnow().isoformat()
    expires_at = int((datetime.utcnow() + timedelta(hours=24)).timestamp())
    decision_id = ai_result.get("decisionId", f"D-{int(datetime.utcnow().timestamp())}")
    agent_response = build_chat_response(ai_result)
    records_written = 0

    # 1: AI_DECISION record
    ai_decision = {
        "memberId": member_id,
        "recordType": f"AI_DECISION#{decision_id}",
        "decisionId": decision_id,
        "gsiRecordType": "AI_DECISION",
        "sessionId": session_id,
        "analysis": ai_result.get("analysis", ""),
        "riskAssessment": ai_result.get("riskAssessment", ""),
        "claimsInsight": ai_result.get("claimsInsight", ""),
        "careHistoryInsight": ai_result.get("careHistoryInsight", ""),
        "medicationInsight": ai_result.get("medicationInsight", ""),
        "confidence": str(ai_result.get("confidence", 0)),
        "model": ai_result.get("model", ""),
        "talkingPoints": ai_result.get("talkingPoints", []),
        "updatedAt": now,
        "expiresAt": expires_at,
    }
    table.put_item(Item=clean(ai_decision))
    records_written += 1

    # 2: CARE_GAP records
    for i, gap in enumerate(ai_result.get("careGaps", [])):
        gap_id = f"GAP-{int(datetime.utcnow().timestamp())}-{i}"
        gap_record = {
            "memberId": member_id,
            "recordType": f"CARE_GAP#{gap_id}",
            "gapId": gap_id,
            "gsiRecordType": "CARE_GAP",
            "decisionId": decision_id,
            "type": gap.get("type", ""),
            "priority": gap.get("priority", ""),
            "protocol": gap.get("protocol", ""),
            "dueWithin": gap.get("dueWithin", ""),
            "details": gap.get("details", ""),
            "actionItems": gap.get("actionItems", []),
            "status": "Open",
            "updatedAt": now,
            "expiresAt": expires_at,
        }
        table.put_item(Item=clean(gap_record))
        records_written += 1

    # 3: INTERVENTION records
    for i, inv in enumerate(ai_result.get("recommendedInterventions", [])):
        inv_id = f"INT-{int(datetime.utcnow().timestamp())}-{i}"
        inv_record = {
            "memberId": member_id,
            "recordType": f"INTERVENTION#{inv_id}",
            "interventionId": inv_id,
            "gsiRecordType": "INTERVENTION",
            "decisionId": decision_id,
            "type": inv.get("type", ""),
            "target": inv.get("target", ""),
            "message": inv.get("message", ""),
            "linkedGap": inv.get("linkedGap", ""),
            "system": inv.get("system", ""),
            "status": "Triggered",
            "updatedAt": now,
            "expiresAt": expires_at,
        }
        table.put_item(Item=clean(inv_record))
        records_written += 1

    # 4: SUMMARY record
    summary_record = {
        "memberId": member_id,
        "recordType": f"SUMMARY#{decision_id}",
        "decisionId": decision_id,
        "gsiRecordType": "SUMMARY",
        "sessionId": session_id,
        "talkingPoints": ai_result.get("talkingPoints", []),
        "agentResponse": agent_response,
        "updatedAt": now,
        "expiresAt": expires_at,
    }
    table.put_item(Item=clean(summary_record))
    records_written += 1

    # 5: SESSION record (preserves existing behavior)
    session_record = {
        "memberId": member_id,
        "recordType": f"SESSION#{session_id}",
        "sessionId": session_id,
        "decisionId": decision_id,
        "gsiRecordType": "SESSION",
        "updatedAt": now,
        "expiresAt": expires_at,
        "userMessage": user_message,
        "agentResponse": agent_response,
        "analysis": ai_result.get("analysis", ""),
        "riskAssessment": ai_result.get("riskAssessment", ""),
        "claimsInsight": ai_result.get("claimsInsight", ""),
        "careHistoryInsight": ai_result.get("careHistoryInsight", ""),
        "medicationInsight": ai_result.get("medicationInsight", ""),
        "confidence": str(ai_result.get("confidence", 0)),
        "model": ai_result.get("model", ""),
        "talkingPoints": ai_result.get("talkingPoints", []),
        "careGaps": [
            {
                "gapId": f"GAP-{int(datetime.utcnow().timestamp())}-{i}",
                "type": g.get("type", ""),
                "priority": g.get("priority", ""),
                "protocol": g.get("protocol", ""),
                "dueWithin": g.get("dueWithin", ""),
                "details": g.get("details", ""),
                "actionItems": g.get("actionItems", []),
                "status": "Open"
            }
            for i, g in enumerate(ai_result.get("careGaps", []))
        ],
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
    table.put_item(Item=clean(session_record))
    records_written += 1

    logger.info("Wrote %d records for %s (AI_DECISION + %d CARE_GAPs + %d INTERVENTIONs + SUMMARY + SESSION)",
                records_written, member_id,
                len(ai_result.get("careGaps", [])),
                len(ai_result.get("recommendedInterventions", [])))

    return {
        "memberId": member_id,
        "decisionId": decision_id,
        "sessionId": session_id,
        "recordsWritten": records_written,
        "careGaps": len(ai_result.get("careGaps", [])),
        "interventions": len(ai_result.get("recommendedInterventions", [])),
        "agentResponse": agent_response,
        "status": "success"
    }


def clean(record):
    """Remove empty strings and None values (DynamoDB constraint)."""
    return {k: v for k, v in record.items() if v != "" and v is not None}


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
