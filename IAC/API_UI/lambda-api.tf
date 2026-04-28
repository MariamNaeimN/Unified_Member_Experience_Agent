# =============================================================================
# Lambda: Chat API — Receives Sarah's question, starts Step Functions
# Endpoints:
#   POST /chat     — Send a message to the agent
#   GET  /chat     — Get chat history for a member
#   GET  /members  — Search members by name or ID
# =============================================================================

resource "aws_cloudwatch_log_group" "chat_api" {
  name              = "/aws/lambda/${var.project_name}-chat-api-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "chat_api" {
  function_name = "${var.project_name}-chat-api-${var.environment}"
  description   = "Chat API: receives care manager questions, starts orchestration, returns results"
  role          = aws_iam_role.lambda_api_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.chat_api.output_path
  source_code_hash = data.archive_file.chat_api.output_base64sha256

  environment {
    variables = {
      STEP_FUNCTION_ARN         = local.step_function_arn
      DYNAMODB_TABLE_NAME       = var.dynamodb_table_name
      DYNAMODB_AGENT_TABLE_NAME = var.dynamodb_agent_table_name
      ENVIRONMENT               = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-chat-api"
    Role = "Chat API Gateway Handler"
  }

  depends_on = [aws_cloudwatch_log_group.chat_api]
}

data "archive_file" "chat_api" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-chat-api.zip"

  source {
    content  = <<-PYTHON
import json
import os
import logging
import boto3
import re
import time
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sfn = boto3.client("stepfunctions")
dynamodb = boto3.resource("dynamodb")

SFN_ARN = os.environ["STEP_FUNCTION_ARN"]
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
AGENT_TABLE_NAME = os.environ.get("DYNAMODB_AGENT_TABLE_NAME", TABLE_NAME)


def lambda_handler(event, context):
    """
    API Gateway handler for the chat agent.
    Routes: POST /chat, GET /chat, GET /members
    """
    http_method = event.get("httpMethod", "")
    path = event.get("path", "")
    body = json.loads(event.get("body", "{}") or "{}")
    params = event.get("queryStringParameters") or {}

    # Get authenticated user from Cognito
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    user_email = claims.get("email", "unknown")
    user_name = claims.get("name", user_email)

    logger.info("Request: %s %s from %s", http_method, path, user_email)

    try:
        if path == "/chat" and http_method == "POST":
            return handle_chat(body, user_email, user_name)
        elif path == "/chat" and http_method == "GET":
            return handle_get_chat(params)
        elif path == "/members" and http_method == "GET":
            return handle_search_members(params)
        elif path == "/members/profile" and http_method == "GET":
            return handle_get_profile(params)
        elif path == "/notifications" and http_method == "GET":
            return handle_get_notifications(params)
        elif path.startswith("/notifications/") and http_method == "PATCH":
            notif_id = path.split("/")[-1]
            return handle_update_notification(body, params, notif_id)
        else:
            return response(404, {"error": "Not found"})
    except Exception as e:
        logger.error("Error: %s", str(e))
        return response(500, {"error": str(e)})


def handle_chat(body, user_email, user_name):
    """
    POST /chat
    Body: { "memberId": "M-10042", "message": "Tell me about this member", "sessionId": "optional" }
    Starts Step Functions orchestration and waits for result.
    """
    member_id = body.get("memberId", "")
    message = body.get("message", "")
    session_id = body.get("sessionId", "session-" + str(int(time.time())))
    force = body.get("forceReanalyze", False)

    if not member_id:
        # Try to extract member ID from the message
        match = re.search(r"M-\d{5}", message)
        if match:
            member_id = match.group()
        else:
            return response(400, {"error": "memberId is required or include it in your message (e.g., M-10042)"})

    if not message:
        message = "Analyze member " + member_id

    logger.info("Chat: user=%s, member=%s, message=%s", user_email, member_id, message[:100])

    # Start Step Functions execution
    execution = sfn.start_execution(
        stateMachineArn=SFN_ARN,
        input=json.dumps({
            "memberId": member_id,
            "userMessage": message,
            "sessionId": session_id,
            "forceReanalyze": force,
            "requestedBy": user_email
        })
    )

    execution_arn = execution["executionArn"]
    logger.info("Started execution: %s", execution_arn)

    # Poll for completion (max 60 seconds)
    max_wait = 55
    waited = 0
    poll_interval = 2

    while waited < max_wait:
        time.sleep(poll_interval)
        waited += poll_interval

        status = sfn.describe_execution(executionArn=execution_arn)
        exec_status = status["status"]

        if exec_status == "SUCCEEDED":
            output = json.loads(status.get("output", "{}"))
            is_cached = output.get("status") == "cached"

            if is_cached:
                # Cached path — data is in output.result
                cached = output.get("result", {})
                agent_response = cached.get("summary", "Profile analysis returned from cache.")
                return response(200, {
                    "memberId": member_id,
                    "sessionId": session_id,
                    "agentResponse": agent_response,
                    "decisionId": cached.get("decisionId", ""),
                    "careGaps": cached.get("careGaps", 0),
                    "interventions": cached.get("interventions", 0),
                    "status": "success",
                    "cached": True
                })
            else:
                # Fresh analysis path — data is in output.writeResult
                write_result = output.get("writeResult", {})
                agent_response = write_result.get("agentResponse", "Analysis complete.")
                return response(200, {
                    "memberId": member_id,
                    "sessionId": session_id,
                    "agentResponse": agent_response,
                    "decisionId": write_result.get("decisionId", ""),
                    "careGaps": write_result.get("careGaps", 0),
                    "interventions": write_result.get("interventions", 0),
                    "status": "success",
                    "cached": False
                })

        elif exec_status in ("FAILED", "TIMED_OUT", "ABORTED"):
            return response(500, {
                "error": "Orchestration " + exec_status.lower(),
                "executionArn": execution_arn
            })

    return response(202, {
        "message": "Analysis in progress. Check back shortly.",
        "executionArn": execution_arn,
        "memberId": member_id,
        "sessionId": session_id
    })


def handle_get_chat(params):
    """
    GET /chat?memberId=M-10042&sessionId=optional
    Returns chat history for a member.
    """
    member_id = params.get("memberId", "")
    if not member_id:
        return response(400, {"error": "memberId is required"})

    table = dynamodb.Table(AGENT_TABLE_NAME)
    result = table.query(
        KeyConditionExpression=Key("memberId").eq(member_id) & Key("recordType").begins_with("CHAT_HISTORY#")
    )

    chats = []
    for item in result.get("Items", []):
        chats.append({
            "chatId": item.get("chatId", ""),
            "sessionId": item.get("sessionId", ""),
            "userMessage": item.get("userMessage", ""),
            "agentResponse": item.get("agentResponse", ""),
            "timestamp": item.get("updatedAt", "")
        })

    chats.sort(key=lambda x: x.get("timestamp", ""))

    return response(200, {
        "memberId": member_id,
        "chatHistory": chats,
        "count": len(chats)
    })


def handle_search_members(params):
    """
    GET /members?search=John+Smith  or  GET /members?search=M-10042
    Searches members by name or ID.
    """
    search = params.get("search", "")
    if not search:
        return response(400, {"error": "search parameter is required"})

    table = dynamodb.Table(TABLE_NAME)

    # If search looks like a member ID
    if re.match(r"M-\d+", search):
        result = table.get_item(
            Key={"memberId": search, "recordType": "MEMBER#" + search}
        )
        item = result.get("Item")
        if item:
            return response(200, {
                "members": [{
                    "memberId": item.get("memberId", ""),
                    "firstName": item.get("firstName", ""),
                    "lastName": item.get("lastName", ""),
                    "planName": item.get("planName", ""),
                    "coverageStatus": item.get("coverageStatus", "")
                }],
                "count": 1
            })
        return response(200, {"members": [], "count": 0})

    # Search by name — scan MEMBER records (fine for demo scale)
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

    return response(200, {"members": matches, "count": len(matches)})


def handle_get_profile(params):
    """
    GET /members/profile?memberId=M-10042
    Returns the full unified profile for a member.
    """
    member_id = params.get("memberId", "")
    if not member_id:
        return response(400, {"error": "memberId is required"})

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

    return response(200, profile)


def handle_get_notifications(params):
    """
    GET /notifications?memberId=M-10042&status=unread
    Returns notifications from SESSION records in the agent table.
    """
    member_id = params.get("memberId", "")
    status_filter = params.get("status", "")

    agent_table = dynamodb.Table(AGENT_TABLE_NAME)

    if member_id:
        result = agent_table.query(
            KeyConditionExpression=Key("memberId").eq(member_id) & Key("recordType").begins_with("SESSION#")
        )
    else:
        result = agent_table.query(
            IndexName="recordType-index",
            KeyConditionExpression=Key("gsiRecordType").eq("SESSION")
        )

    notifications = []
    for item in result.get("Items", []):
        session_id = item.get("sessionId", "")
        created_at = item.get("updatedAt", "")
        for n in item.get("notifications", []):
            if status_filter and n.get("status") != status_filter:
                continue
            notifications.append({
                "sessionId": session_id,
                "memberId": item.get("memberId", ""),
                "type": n.get("type", ""),
                "title": n.get("title", ""),
                "message": n.get("message", ""),
                "priority": n.get("priority", ""),
                "status": n.get("status", "unread"),
                "target": n.get("target", ""),
                "createdAt": created_at
            })

    notifications.sort(key=lambda x: x.get("createdAt", ""), reverse=True)

    return response(200, {
        "notifications": notifications,
        "count": len(notifications),
        "unread": len([n for n in notifications if n["status"] == "unread"])
    })


def handle_update_notification(body, params, notif_id):
    """
    PATCH /notifications/{notifId}?memberId=M-10042
    Body: { "status": "read" } or { "status": "dismissed" }
    """
    member_id = body.get("memberId", "") or params.get("memberId", "")
    new_status = body.get("status", "read")

    if not member_id:
        return response(400, {"error": "memberId is required"})
    if new_status not in ("read", "dismissed", "unread"):
        return response(400, {"error": "status must be read, dismissed, or unread"})

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
        return response(200, {"notificationId": notif_id, "status": new_status})
    except Exception as e:
        return response(500, {"error": str(e)})


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
        },
        "body": json.dumps(body, default=str)
    }
PYTHON
    filename = "handler.py"
  }
}
