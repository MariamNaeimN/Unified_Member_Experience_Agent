# =============================================================================
# Lambda: Execute Workflows - Step 4 of orchestration
# Reads interventions from write-back results and routes to downstream systems:
#   SMS -> SNS (patient notifications)
#   TASK -> SNS (care team alerts) + DynamoDB status update
#   ALERT -> SNS (pharmacy alerts) + DynamoDB status update
#   REFERRAL -> SNS (care team alerts) + DynamoDB status update
# =============================================================================

resource "aws_cloudwatch_log_group" "execute_workflows" {
  name              = "/aws/lambda/${var.project_name}-execute-workflows-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "execute_workflows" {
  function_name = "${var.project_name}-execute-workflows-${var.environment}"
  description   = "Step 4: Route interventions to downstream systems (SNS, care management, pharmacy)"
  role          = aws_iam_role.lambda_orch_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = 256

  filename         = data.archive_file.execute_workflows.output_path
  source_code_hash = data.archive_file.execute_workflows.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME       = var.dynamodb_table_name
      DYNAMODB_AGENT_TABLE_NAME = var.dynamodb_agent_table_name
      SNS_PATIENT_TOPIC_ARN     = aws_sns_topic.patient_notifications.arn
      SNS_CARE_TEAM_TOPIC_ARN   = aws_sns_topic.care_team_alerts.arn
      SNS_PHARMACY_TOPIC_ARN    = aws_sns_topic.pharmacy_alerts.arn
      ENVIRONMENT               = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-execute-workflows"
    Role = "Step 4 - Trigger Downstream Workflows"
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.execute_workflows]
}

data "archive_file" "execute_workflows" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-execute-workflows.zip"

  source {
    content  = <<-PYTHON
import json
import os
import logging
import boto3
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client("sns")
dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
AGENT_TABLE_NAME = os.environ.get("DYNAMODB_AGENT_TABLE_NAME", TABLE_NAME)
PATIENT_TOPIC = os.environ["SNS_PATIENT_TOPIC_ARN"]
CARE_TEAM_TOPIC = os.environ["SNS_CARE_TEAM_TOPIC_ARN"]
PHARMACY_TOPIC = os.environ["SNS_PHARMACY_TOPIC_ARN"]

# Map intervention types to SNS topics
TOPIC_MAP = {
    "SMS": PATIENT_TOPIC,
    "TASK": CARE_TEAM_TOPIC,
    "ALERT": PHARMACY_TOPIC,
    "REFERRAL": CARE_TEAM_TOPIC,
}


def lambda_handler(event, context):
    """
    Execute workflow triggers for each intervention.
    Reads the write-back results, publishes to SNS, updates DynamoDB status.

    Input: { "memberId": "M-10042", "aiResult": {...}, "writeResult": {...} }
    Output: { "memberId": "M-10042", "workflowsExecuted": N, "results": [...] }
    """
    member_id = event.get("memberId")
    ai_result = event.get("aiResult", {})
    session_id = event.get("sessionId", "")
    interventions = ai_result.get("recommendedInterventions", [])

    if not interventions:
        logger.info("No interventions to execute for %s", member_id)
        return {
            "memberId": member_id,
            "workflowsExecuted": 0,
            "workflowsFailed": 0,
            "results": [],
            "status": "no_interventions"
        }

    table = dynamodb.Table(TABLE_NAME)
    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    now = datetime.utcnow().isoformat()
    results = []

    # Get member name from source table
    member_name = ""
    try:
        member_record = table.get_item(
            Key={"memberId": member_id, "recordType": "MEMBER#" + member_id}
        )
        item = member_record.get("Item", {})
        member_name = item.get("firstName", "") + " " + item.get("lastName", "")
    except Exception as e:
        logger.warning("Could not fetch member name: %s", str(e))

    for i, intervention in enumerate(interventions):
        int_type = intervention.get("type", "TASK")
        target = intervention.get("target", "")
        message = intervention.get("message", "")
        linked_gap = intervention.get("linkedGap", "")
        system = intervention.get("system", "")

        # Select SNS topic
        topic_arn = TOPIC_MAP.get(int_type, CARE_TEAM_TOPIC)

        # Build notification
        subject = "[" + int_type + "] " + member_id + " - " + linked_gap
        body = build_notification(member_id, member_name, int_type, target, message, linked_gap)

        # Publish to SNS
        try:
            sns_response = sns.publish(
                TopicArn=topic_arn,
                Subject=subject[:100],
                Message=body,
                MessageAttributes={
                    "memberId": {"DataType": "String", "StringValue": member_id},
                    "interventionType": {"DataType": "String", "StringValue": int_type},
                    "priority": {"DataType": "String", "StringValue": intervention.get("priority", "MEDIUM")},
                }
            )
            message_id = sns_response.get("MessageId", "")
            status = "Delivered"
            logger.info("Published %s to %s: %s", int_type, topic_arn.split(":")[-1], message_id)
        except Exception as e:
            message_id = ""
            status = "Failed"
            logger.error("Failed to publish %s: %s", int_type, str(e))

        # Update intervention status in agent DynamoDB table
        decision_id = ai_result.get("decisionId", "")
        int_id = "INT-" + str(int(datetime.utcnow().timestamp())) + "-" + str(i)

        try:
            response = agent_table.query(
                KeyConditionExpression=boto3.dynamodb.conditions.Key("memberId").eq(member_id) &
                    boto3.dynamodb.conditions.Key("recordType").begins_with("SESSION#"),
            )
            # Update the intervention status in the session record
            for item in response.get("Items", []):
                interventions_list = item.get("interventions", [])
                for inv_item in interventions_list:
                    if inv_item.get("message") == message and inv_item.get("status") == "Triggered":
                        inv_item["status"] = status
                        inv_item["snsMessageId"] = message_id
                        inv_item["deliveredAt"] = now
                        break
                agent_table.update_item(
                    Key={"memberId": member_id, "recordType": item["recordType"]},
                    UpdateExpression="SET interventions = :inv",
                    ExpressionAttributeValues={":inv": interventions_list}
                )
                break
        except Exception as e:
            logger.warning("Could not update intervention status: %s", str(e))

        results.append({
            "type": int_type,
            "target": target,
            "linkedGap": linked_gap,
            "status": status,
            "snsMessageId": message_id,
            "topic": topic_arn.split(":")[-1]
        })

    executed = len([r for r in results if r["status"] == "Delivered"])
    failed = len([r for r in results if r["status"] == "Failed"])

    logger.info("Workflows complete for %s: %d delivered, %d failed", member_id, executed, failed)

    return {
        "memberId": member_id,
        "workflowsExecuted": executed,
        "workflowsFailed": failed,
        "results": results,
        "status": "success" if failed == 0 else "partial"
    }


def build_notification(member_id, member_name, int_type, target, message, linked_gap):
    """Build a formatted notification message."""
    parts = []
    parts.append("=" * 50)
    parts.append("MEMBER EXPERIENCE AGENT - WORKFLOW TRIGGER")
    parts.append("=" * 50)
    parts.append("")
    parts.append("Member: " + member_name + " (" + member_id + ")")
    parts.append("Action Type: " + int_type)
    parts.append("Target: " + target)
    parts.append("Care Gap: " + linked_gap)
    parts.append("")
    parts.append("Message:")
    parts.append(message)
    parts.append("")
    parts.append("Triggered at: " + datetime.utcnow().isoformat() + " UTC")
    parts.append("=" * 50)
    return "\n".join(parts)
PYTHON
    filename = "handler.py"
  }
}
