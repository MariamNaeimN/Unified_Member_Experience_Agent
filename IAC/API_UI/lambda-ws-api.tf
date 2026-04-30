# =============================================================================
# Lambda: ws-api — Handles non-chat WebSocket routes
# Routes: getMembers, getMemberProfile, getNotifications, updateNotification, getChatHistory
# Reuses exact logic from lambda-api.tf handlers
# =============================================================================

resource "aws_cloudwatch_log_group" "ws_api" {
  name              = "/aws/lambda/${var.project_name}-ws-api-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "ws_api" {
  function_name = "${var.project_name}-ws-api-${var.environment}"
  description   = "WebSocket API handler: members, notifications, chat history"
  role          = aws_iam_role.ws_api_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.ws_api.output_path
  source_code_hash = data.archive_file.ws_api.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME       = var.dynamodb_table_name
      DYNAMODB_AGENT_TABLE_NAME = var.dynamodb_agent_table_name
    }
  }

  tags = {
    Name = "${var.project_name}-ws-api"
    Role = "WebSocket API Handler"
  }

  depends_on = [aws_cloudwatch_log_group.ws_api]
}

data "archive_file" "ws_api" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-ws-api.zip"

  source {
    content  = <<-PYTHON
import json
import os
import re
import logging
import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
AGENT_TABLE_NAME = os.environ["DYNAMODB_AGENT_TABLE_NAME"]


def lambda_handler(event, context):
    """
    WebSocket API handler for non-chat operations.
    Routes based on requestContext.routeKey.
    """
    connection_id = event["requestContext"]["connectionId"]
    domain_name = event["requestContext"]["domainName"]
    stage = event["requestContext"]["stage"]
    route_key = event["requestContext"]["routeKey"]
    endpoint_url = f"https://{domain_name}/{stage}"

    body = json.loads(event.get("body", "{}") or "{}")
    request_id = body.get("requestId", "")

    logger.info("API request: route=%s, connection=%s, requestId=%s", route_key, connection_id, request_id)

    # Verify authentication via CONNECTION# record
    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    conn_result = agent_table.get_item(
        Key={"memberId": f"CONNECTION#{connection_id}", "recordType": "META"}
    )
    if not conn_result.get("Item"):
        send_to_connection(connection_id, endpoint_url, {
            "requestId": request_id,
            "type": "error",
            "message": "Not authenticated"
        })
        return {"statusCode": 401}

    try:
        if route_key == "getMembers":
            result = handle_get_members(body)
        elif route_key == "getMemberProfile":
            result = handle_get_member_profile(body)
        elif route_key == "getNotifications":
            result = handle_get_notifications(body)
        elif route_key == "updateNotification":
            result = handle_update_notification(body)
        elif route_key == "getChatHistory":
            result = handle_get_chat_history(body)
        else:
            result = {"type": "error", "message": f"Unknown action: {route_key}"}

        result["requestId"] = request_id
        send_to_connection(connection_id, endpoint_url, result)

    except Exception as e:
        logger.error("Error handling %s: %s", route_key, str(e))
        send_to_connection(connection_id, endpoint_url, {
            "requestId": request_id,
            "type": "error",
            "message": str(e)
        })

    return {"statusCode": 200}


def send_to_connection(connection_id, endpoint_url, message):
    """Send a JSON message to a WebSocket client via the Management API."""
    try:
        apigw = boto3.client("apigatewaymanagementapi", endpoint_url=endpoint_url)
        apigw.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(message, default=str).encode("utf-8")
        )
        return True
    except Exception as e:
        logger.error("Error sending to connection %s: %s", connection_id, str(e))
        return False


def handle_get_members(body):
    """
    getMembers action — searches members by name or ID.
    Same logic as handle_search_members in lambda-api.tf.
    """
    search = body.get("search", "")
    if not search:
        # Return all members when no search provided
        table = dynamodb.Table(TABLE_NAME)
        result = table.query(
            IndexName="recordType-index",
            KeyConditionExpression=Key("gsiRecordType").eq("MEMBER")
        )
        members = []
        for item in result.get("Items", []):
            members.append({
                "memberId": item.get("memberId", ""),
                "firstName": item.get("firstName", ""),
                "lastName": item.get("lastName", ""),
                "planName": item.get("planName", ""),
                "coverageStatus": item.get("coverageStatus", "")
            })
        return {"type": "members", "members": members, "count": len(members)}

    table = dynamodb.Table(TABLE_NAME)

    # If search looks like a member ID
    if re.match(r"M-\d+", search):
        result = table.get_item(
            Key={"memberId": search, "recordType": "MEMBER#" + search}
        )
        item = result.get("Item")
        if item:
            return {
                "type": "members",
                "members": [{
                    "memberId": item.get("memberId", ""),
                    "firstName": item.get("firstName", ""),
                    "lastName": item.get("lastName", ""),
                    "planName": item.get("planName", ""),
                    "coverageStatus": item.get("coverageStatus", "")
                }],
                "count": 1
            }
        return {"type": "members", "members": [], "count": 0}

    # Search by name — scan MEMBER records
    result = table.query(
        IndexName="recordType-index",
        KeyConditionExpression=Key("gsiRecordType").eq("MEMBER")
    )

    search_lower = search.lower()
    matches = []
    for item in result.get("Items", []):
        full_name = (item.get("firstName", "") + " " + item.get("lastName", "")).lower()
        if search_lower in full_name:
            matches.append({
                "memberId": item.get("memberId", ""),
                "firstName": item.get("firstName", ""),
                "lastName": item.get("lastName", ""),
                "planName": item.get("planName", ""),
                "coverageStatus": item.get("coverageStatus", "")
            })

    return {"type": "members", "members": matches, "count": len(matches)}


def handle_get_member_profile(body):
    """
    getMemberProfile action — returns full unified profile.
    Same logic as handle_get_profile in lambda-api.tf.
    """
    member_id = body.get("memberId", "")
    if not member_id:
        return {"type": "error", "message": "memberId is required"}

    table = dynamodb.Table(TABLE_NAME)
    result = table.query(
        KeyConditionExpression=Key("memberId").eq(member_id)
    )

    items = result.get("Items", [])
    profile = {"memberId": member_id}

    for item in items:
        rt = item.get("recordType", "")
        item_clean = json.loads(json.dumps(item, default=str))

        if rt.startswith("MEMBER#"):
            profile["member"] = item_clean
        elif rt.startswith("PATIENT#"):
            profile["patient"] = item_clean
        elif rt.startswith("CONDITION#"):
            profile.setdefault("conditions", []).append(item_clean)
        elif rt.startswith("CLAIM#"):
            profile.setdefault("claims", []).append(item_clean)
        elif rt.startswith("PHARMACY#"):
            profile.setdefault("pharmacy", []).append(item_clean)
        elif rt.startswith("CARE_EVENT#"):
            profile.setdefault("careEvents", []).append(item_clean)

    # Also fetch agent output for this member
    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    agent_result = agent_table.query(
        KeyConditionExpression=Key("memberId").eq(member_id)
    )
    for item in agent_result.get("Items", []):
        rt = item.get("recordType", "")
        item_clean = json.loads(json.dumps(item, default=str))

        if rt.startswith("AI_DECISION#"):
            profile.setdefault("aiDecisions", []).append(item_clean)
        elif rt.startswith("CARE_GAP#"):
            profile.setdefault("careGaps", []).append(item_clean)
        elif rt.startswith("INTERVENTION#"):
            profile.setdefault("interventions", []).append(item_clean)
        elif rt.startswith("SUMMARY#"):
            profile.setdefault("summaries", []).append(item_clean)
        elif rt.startswith("SESSION#"):
            # Store sessions separately — don't duplicate into aiDecisions
            profile.setdefault("sessions", []).append(item_clean)

    profile["type"] = "memberProfile"
    return profile


def handle_get_notifications(body):
    """
    getNotifications action — returns notifications from SESSION records.
    Optimized: limits results and only projects needed fields.
    """
    member_id = body.get("memberId", "")
    status_filter = body.get("status", "")

    agent_table = dynamodb.Table(AGENT_TABLE_NAME)

    if member_id:
        result = agent_table.query(
            KeyConditionExpression=Key("memberId").eq(member_id) & Key("recordType").begins_with("SESSION#"),
            ProjectionExpression="memberId,sessionId,updatedAt,notifications",
            ScanIndexForward=False,
            Limit=5
        )
    else:
        # Fetch all SESSION records from GSI, paginate if needed
        items = []
        query_params = {
            "IndexName": "recordType-index",
            "KeyConditionExpression": Key("gsiRecordType").eq("SESSION"),
            "ProjectionExpression": "memberId,sessionId,updatedAt,notifications",
        }
        while True:
            result = agent_table.query(**query_params)
            items.extend(result.get("Items", []))
            if "LastEvaluatedKey" not in result or len(items) >= 500:
                break
            query_params["ExclusiveStartKey"] = result["LastEvaluatedKey"]
        result = {"Items": items}

    notifications = []
    seen_members = set()
    for item in result.get("Items", []):
        mid = item.get("memberId", "")
        # Only take the latest session per member to avoid duplicates
        if mid in seen_members:
            continue
        seen_members.add(mid)
        session_id = item.get("sessionId", "")
        created_at = item.get("updatedAt", "")
        for n in item.get("notifications", []):
            if status_filter and n.get("status") != status_filter:
                continue
            notifications.append({
                "sessionId": session_id,
                "memberId": mid,
                "type": n.get("type", ""),
                "title": n.get("title", ""),
                "message": n.get("message", ""),
                "priority": n.get("priority", ""),
                "status": n.get("status", "unread"),
                "target": n.get("target", ""),
                "createdAt": created_at
            })

    notifications.sort(key=lambda x: x.get("createdAt", ""), reverse=True)

    return {
        "type": "notifications",
        "notifications": notifications[:100],
        "count": len(notifications),
        "unread": len([n for n in notifications if n["status"] == "unread"])
    }


def handle_update_notification(body):
    """
    updateNotification action — updates notification status.
    Same logic as handle_update_notification in lambda-api.tf.
    """
    member_id = body.get("memberId", "")
    notif_id = body.get("notificationId", "")
    new_status = body.get("status", "read")

    if not member_id:
        return {"type": "error", "message": "memberId is required"}
    if not notif_id:
        return {"type": "error", "message": "notificationId is required"}
    if new_status not in ("read", "dismissed", "unread"):
        return {"type": "error", "message": "status must be read, dismissed, or unread"}

    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    try:
        agent_table.update_item(
            Key={"memberId": member_id, "recordType": "NOTIFICATION#" + notif_id},
            UpdateExpression="SET #s = :status, updatedAt = :now",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":status": new_status,
                ":now": __import__("datetime").datetime.utcnow().isoformat()
            }
        )
        return {"type": "notificationUpdated", "notificationId": notif_id, "status": new_status}
    except Exception as e:
        return {"type": "error", "message": str(e)}


def handle_get_chat_history(body):
    """
    getChatHistory action — returns chat history for a member.
    Same logic as handle_get_chat in lambda-api.tf.
    """
    member_id = body.get("memberId", "")
    if not member_id:
        return {"type": "error", "message": "memberId is required"}

    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    result = agent_table.query(
        KeyConditionExpression=Key("memberId").eq(member_id) & Key("recordType").begins_with("SESSION#")
    )

    chats = []
    for item in result.get("Items", []):
        chats.append({
            "sessionId": item.get("sessionId", ""),
            "userMessage": item.get("userMessage", ""),
            "agentResponse": item.get("agentResponse", ""),
            "timestamp": item.get("updatedAt", ""),
            "decisionId": item.get("decisionId", ""),
            "careGaps": len(item.get("careGaps", [])),
            "interventions": len(item.get("interventions", []))
        })

    chats.sort(key=lambda x: x.get("timestamp", ""))

    return {
        "type": "chatHistory",
        "memberId": member_id,
        "chatHistory": chats,
        "count": len(chats)
    }
PYTHON
    filename = "handler.py"
  }
}
