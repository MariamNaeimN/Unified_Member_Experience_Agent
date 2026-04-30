# =============================================================================
# Lambda: agent-tools — REST API handler for all 12 MCP tools
# Mirrors Agent_Member/server.py logic as a Lambda-backed HTTP endpoint
# =============================================================================

resource "aws_cloudwatch_log_group" "agent_tools" {
  name              = "/aws/lambda/${var.project_name}-agent-tools-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "agent_tools" {
  function_name = "${var.project_name}-agent-tools-${var.environment}"
  description   = "REST API handler exposing all MCP tools over HTTP"
  role          = aws_iam_role.agent_tools_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = 15
  memory_size   = 512

  filename         = data.archive_file.agent_tools.output_path
  source_code_hash = data.archive_file.agent_tools.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME       = var.dynamodb_table_name
      DYNAMODB_AGENT_TABLE_NAME = var.dynamodb_agent_table_name
    }
  }

  tags = {
    Name = "${var.project_name}-agent-tools"
    Role = "MCP Tools REST API Handler"
  }

  depends_on = [aws_cloudwatch_log_group.agent_tools]
}

data "archive_file" "agent_tools" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-agent-tools.zip"

  source {
    content  = <<-PYTHON
import json
import os
import re
import logging
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
AGENT_TABLE_NAME = os.environ["DYNAMODB_AGENT_TABLE_NAME"]

# ── Available tools registry ────────────────────────────────────────────────

TOOLS = [
    {"name": "search_member", "method": "POST", "description": "Search for a member by name or ID", "body": {"query": "John Smith"}},
    {"name": "get_member_analysis", "method": "POST", "description": "Get latest AI analysis for a member", "body": {"memberId": "M-10042"}},
    {"name": "get_member_care_gaps", "method": "POST", "description": "List open care gaps for a member", "body": {"memberId": "M-10042"}},
    {"name": "get_member_interventions", "method": "POST", "description": "List recommended interventions for a member", "body": {"memberId": "M-10042"}},
    {"name": "get_member_profile", "method": "POST", "description": "Get full member profile (demographics + clinical)", "body": {"memberId": "M-10042"}},
    {"name": "get_member_conditions", "method": "POST", "description": "Get active conditions/diagnoses for a member", "body": {"memberId": "M-10042"}},
    {"name": "get_member_medications", "method": "POST", "description": "Get current medications and adherence for a member", "body": {"memberId": "M-10042"}},
    {"name": "get_member_claims", "method": "POST", "description": "Get claims history for a member", "body": {"memberId": "M-10042"}},
    {"name": "get_member_care_events", "method": "POST", "description": "Get care events (visits, ER, hospitalizations) for a member", "body": {"memberId": "M-10042"}},
    {"name": "get_all_members_summary", "method": "GET", "description": "Return summary list of all members", "body": None},
    {"name": "get_member_notifications", "method": "POST", "description": "Get notifications (optionally filtered by member)", "body": {"memberId": "M-10042"}},
    {"name": "get_high_risk_members", "method": "POST", "description": "Return members with risk score above threshold", "body": {"min_risk_score": 80}},
]


# ── Helpers ──────────────────────────────────────────────────────────────────

def _source_table():
    return dynamodb.Table(TABLE_NAME)


def _agent_table():
    return dynamodb.Table(AGENT_TABLE_NAME)


def _convert_decimals(obj):
    """Recursively convert DynamoDB Decimal values to int/float."""
    if isinstance(obj, list):
        return [_convert_decimals(i) for i in obj]
    if isinstance(obj, dict):
        return {k: _convert_decimals(v) for k, v in obj.items()}
    if isinstance(obj, Decimal):
        return int(obj) if obj == int(obj) else float(obj)
    return obj


def _safe_str(val, default=""):
    if val is None:
        return default
    return str(val)


def _resolve_member_id(identifier):
    """Resolve a member identifier (ID or name) to a memberId. Optimized for speed."""
    if not identifier:
        return None
    identifier = identifier.strip()
    if re.match(r"M-\d+", identifier, re.IGNORECASE):
        return identifier.upper()

    table = _source_table()
    search_lower = identifier.lower()
    response = table.query(
        IndexName="recordType-index",
        KeyConditionExpression=Key("gsiRecordType").eq("MEMBER"),
        Limit=50,  # Fast: only check first 50 members
    )
    for item in response.get("Items", []):
        full_name = (_safe_str(item.get("firstName")) + " " + _safe_str(item.get("lastName"))).lower()
        if search_lower in full_name or search_lower == _safe_str(item.get("firstName")).lower() or search_lower == _safe_str(item.get("lastName")).lower():
            return item.get("memberId")
    return None


def _cors_response(status_code, body):
    """Return an API Gateway proxy response with CORS headers."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
        },
        "body": json.dumps(body, default=str),
    }


# ── Lambda handler ───────────────────────────────────────────────────────────

def lambda_handler(event, context):
    """
    API Gateway proxy handler.
    Routes:
      GET  /tools              → list available tools
      POST /tools/{toolName}   → invoke a specific tool
    """
    http_method = event.get("httpMethod", "")
    path = event.get("path", "")
    path_params = event.get("pathParameters") or {}
    tool_name = path_params.get("toolName", "")

    logger.info("Request: %s %s tool=%s", http_method, path, tool_name)

    # Handle CORS preflight
    if http_method == "OPTIONS":
        return _cors_response(200, {"message": "OK"})

    # GET /tools — list all tools
    if path == "/tools" and http_method == "GET":
        return _cors_response(200, {"tools": TOOLS, "count": len(TOOLS)})

    # GET /tools/get_all_members_summary — no body needed
    if tool_name == "get_all_members_summary" and http_method == "GET":
        result = _get_all_members_summary()
        return _cors_response(200, result)

    # POST /tools/{toolName}
    if not tool_name:
        return _cors_response(400, {"error": "Missing toolName in path"})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _cors_response(400, {"error": "Invalid JSON body"})

    try:
        result = _route_tool(tool_name, body)
        return _cors_response(200, result)
    except Exception as e:
        logger.exception("Tool %s failed", tool_name)
        return _cors_response(500, {"error": str(e)})


def _route_tool(tool_name, body):
    """Route to the appropriate tool function."""
    if tool_name == "search_member":
        query = body.get("query", "")
        if not query:
            return {"error": "query is required"}
        return _search_member(query)

    if tool_name == "get_member_analysis":
        return _member_tool(body, _get_member_analysis)

    if tool_name == "get_member_care_gaps":
        return _member_tool(body, _get_member_care_gaps)

    if tool_name == "get_member_interventions":
        return _member_tool(body, _get_member_interventions)

    if tool_name == "get_member_profile":
        return _member_tool(body, _get_member_profile)

    if tool_name == "get_member_conditions":
        return _member_tool(body, _get_member_conditions)

    if tool_name == "get_member_medications":
        return _member_tool(body, _get_member_medications)

    if tool_name == "get_member_claims":
        return _member_tool(body, _get_member_claims)

    if tool_name == "get_member_care_events":
        return _member_tool(body, _get_member_care_events)

    if tool_name == "get_all_members_summary":
        return _get_all_members_summary()

    if tool_name == "get_member_notifications":
        mid = body.get("memberId")
        if mid:
            mid = _resolve_member_id(mid)
        return _get_member_notifications(mid)

    if tool_name == "get_high_risk_members":
        threshold = body.get("min_risk_score", 80)
        return _get_high_risk_members(int(threshold))

    return {"error": f"Unknown tool: {tool_name}"}


def _member_tool(body, handler_fn):
    """Common pattern: resolve memberId then call handler."""
    identifier = body.get("memberId", "")
    if not identifier:
        return {"error": "memberId is required"}
    member_id = _resolve_member_id(identifier)
    if not member_id:
        return {"error": f"Member not found: {identifier}"}
    return handler_fn(member_id)


# ── Tool implementations (mirrors server.py) ────────────────────────────────

def _search_member(query):
    """Search for member by name or ID. Optimized with early exit."""
    table = _source_table()
    query = query.strip()

    # Direct ID lookup - fastest path
    if re.match(r"M-\d+", query, re.IGNORECASE):
        mid = query.upper()
        response = table.get_item(Key={"memberId": mid, "recordType": f"MEMBER#{mid}"})
        item = response.get("Item")
        if item:
            item = _convert_decimals(item)
            return {"members": [{"memberId": item.get("memberId"), "firstName": item.get("firstName"), "lastName": item.get("lastName"), "planName": item.get("planName"), "riskScore": item.get("riskScore"), "gender": item.get("gender"), "dob": item.get("dob"), "coverageStatus": item.get("coverageStatus")}], "count": 1}
        return {"members": [], "count": 0, "message": f"No member found with ID {mid}"}

    # Name search - limit to 50 for speed, return first match immediately
    search_lower = query.lower()
    response = table.query(IndexName="recordType-index", KeyConditionExpression=Key("gsiRecordType").eq("MEMBER"), Limit=50)
    matches = []
    for item in response.get("Items", []):
        item = _convert_decimals(item)
        full_name = (_safe_str(item.get("firstName")) + " " + _safe_str(item.get("lastName"))).lower()
        if search_lower in full_name:
            matches.append({"memberId": item.get("memberId"), "firstName": item.get("firstName"), "lastName": item.get("lastName"), "planName": item.get("planName"), "riskScore": item.get("riskScore"), "gender": item.get("gender"), "dob": item.get("dob"), "coverageStatus": item.get("coverageStatus")})
            if len(matches) >= 5:  # Return early after 5 matches
                break
    return {"members": matches, "count": len(matches)}


def _get_member_analysis(member_id):
    table = _agent_table()
    response = table.query(
        KeyConditionExpression=(
            Key("memberId").eq(member_id)
            & Key("recordType").begins_with("AI_DECISION#")
        ),
        ScanIndexForward=False,
        Limit=1,
    )
    items = response.get("Items", [])
    if not items:
        return {"memberId": member_id, "analysis": None, "message": "No analysis found for this member"}

    item = _convert_decimals(items[0])
    return {
        "memberId": member_id,
        "decisionId": item.get("decisionId"),
        "analysis": item.get("analysis"),
        "riskAssessment": item.get("riskAssessment"),
        "claimsInsight": item.get("claimsInsight"),
        "careHistoryInsight": item.get("careHistoryInsight"),
        "medicationInsight": item.get("medicationInsight"),
        "confidence": item.get("confidence"),
        "model": item.get("model"),
        "talkingPoints": item.get("talkingPoints", []),
        "updatedAt": _safe_str(item.get("updatedAt")),
    }


def _get_member_care_gaps(member_id):
    table = _agent_table()
    response = table.query(
        KeyConditionExpression=(
            Key("memberId").eq(member_id)
            & Key("recordType").begins_with("CARE_GAP#")
        ),
    )
    items = _convert_decimals(response.get("Items", []))
    gaps = [
        {
            "gapId": item.get("gapId"),
            "type": item.get("type"),
            "priority": item.get("priority"),
            "protocol": item.get("protocol"),
            "dueWithin": item.get("dueWithin"),
            "status": item.get("status"),
            "updatedAt": _safe_str(item.get("updatedAt")),
        }
        for item in items
    ]
    return {"memberId": member_id, "careGaps": gaps, "count": len(gaps)}


def _get_member_interventions(member_id):
    table = _agent_table()
    response = table.query(
        KeyConditionExpression=(
            Key("memberId").eq(member_id)
            & Key("recordType").begins_with("INTERVENTION#")
        ),
    )
    items = _convert_decimals(response.get("Items", []))
    interventions = [
        {
            "interventionId": item.get("interventionId"),
            "type": item.get("type"),
            "target": item.get("target"),
            "message": item.get("message"),
            "linkedGap": item.get("linkedGap"),
            "status": item.get("status"),
            "updatedAt": _safe_str(item.get("updatedAt")),
        }
        for item in items
    ]
    return {"memberId": member_id, "interventions": interventions, "count": len(interventions)}


def _get_all_members_summary():
    table = _source_table()
    members = []
    query_params = {
        "IndexName": "recordType-index",
        "KeyConditionExpression": Key("gsiRecordType").eq("MEMBER"),
    }
    while True:
        response = table.query(**query_params)
        for item in response.get("Items", []):
            item = _convert_decimals(item)
            mid = item.get("memberId")
            # Fetch PATIENT# record for riskScore
            risk_score = None
            try:
                patient_resp = table.get_item(Key={"memberId": mid, "recordType": f"PATIENT#{mid}"})
                patient = patient_resp.get("Item")
                if patient:
                    patient = _convert_decimals(patient)
                    risk_score = patient.get("riskScore")
            except Exception:
                pass
            members.append({
                "memberId": mid,
                "firstName": item.get("firstName"),
                "lastName": item.get("lastName"),
                "planName": item.get("planName"),
                "riskScore": risk_score,
            })
        if "LastEvaluatedKey" not in response:
            break
        query_params["ExclusiveStartKey"] = response["LastEvaluatedKey"]
    return {"members": members, "count": len(members)}


def _get_member_notifications(member_id=None):
    table = _agent_table()
    notifications = []

    if member_id:
        response = table.query(
            KeyConditionExpression=(
                Key("memberId").eq(member_id)
                & Key("recordType").begins_with("SESSION#")
            ),
            ScanIndexForward=False,
            Limit=10,
        )
        session_items = response.get("Items", [])
    else:
        session_items = []
        query_params = {
            "IndexName": "recordType-index",
            "KeyConditionExpression": Key("gsiRecordType").eq("SESSION"),
        }
        while True:
            response = table.query(**query_params)
            session_items.extend(response.get("Items", []))
            if "LastEvaluatedKey" not in response or len(session_items) >= 500:
                break
            query_params["ExclusiveStartKey"] = response["LastEvaluatedKey"]

    seen_members = set()
    for item in session_items:
        item = _convert_decimals(item)
        mid = item.get("memberId", "")
        if mid in seen_members:
            continue
        seen_members.add(mid)
        for n in item.get("notifications", []):
            notifications.append({
                "memberId": mid,
                "sessionId": item.get("sessionId"),
                "type": n.get("type"),
                "title": n.get("title"),
                "message": n.get("message"),
                "priority": n.get("priority"),
                "status": n.get("status", "unread"),
                "createdAt": _safe_str(item.get("updatedAt")),
            })

    notifications.sort(key=lambda x: x.get("createdAt", ""), reverse=True)
    return {
        "notifications": notifications,
        "count": len(notifications),
        "unread": sum(1 for n in notifications if n.get("status") == "unread"),
    }


def _get_high_risk_members(min_risk_score=80):
    all_members = _get_all_members_summary()
    high_risk = [
        m for m in all_members["members"]
        if (m.get("riskScore") or 0) >= min_risk_score
    ]
    high_risk.sort(key=lambda m: m.get("riskScore", 0), reverse=True)
    return {"members": high_risk, "count": len(high_risk), "threshold": min_risk_score}


def _get_member_profile(member_id):
    table = _source_table()
    response = table.query(
        KeyConditionExpression=Key("memberId").eq(member_id)
    )
    items = _convert_decimals(response.get("Items", []))

    profile = {"memberId": member_id}
    for item in items:
        rt = item.get("recordType", "")
        if rt.startswith("MEMBER#"):
            profile["member"] = {
                "firstName": item.get("firstName"),
                "lastName": item.get("lastName"),
                "dob": item.get("dob"),
                "gender": item.get("gender"),
                "planName": item.get("planName"),
                "planType": item.get("planType"),
                "coverageStatus": item.get("coverageStatus"),
                "enrollmentDate": item.get("enrollmentDate"),
                "state": item.get("state"),
            }
        elif rt.startswith("PATIENT#"):
            profile["patient"] = {
                "riskScore": item.get("riskScore"),
                "livingSituation": item.get("livingSituation"),
                "allergies": item.get("allergies"),
                "bloodType": item.get("bloodType"),
                "bmi": item.get("bmi"),
                "smokingStatus": item.get("smokingStatus"),
            }

    if "member" not in profile:
        return {"memberId": member_id, "error": "Member not found"}
    return profile


def _get_member_conditions(member_id):
    table = _source_table()
    response = table.query(
        KeyConditionExpression=(
            Key("memberId").eq(member_id)
            & Key("recordType").begins_with("CONDITION#")
        ),
    )
    items = _convert_decimals(response.get("Items", []))
    conditions = [
        {
            "conditionId": item.get("conditionId"),
            "diagnosis": item.get("diagnosis"),
            "icdCode": item.get("icdCode"),
            "severity": item.get("severity"),
            "onsetDate": item.get("onsetDate"),
            "status": item.get("status"),
        }
        for item in items
    ]
    return {"memberId": member_id, "conditions": conditions, "count": len(conditions)}


def _get_member_medications(member_id):
    table = _source_table()
    response = table.query(
        KeyConditionExpression=(
            Key("memberId").eq(member_id)
            & Key("recordType").begins_with("PHARMACY#")
        ),
    )
    items = _convert_decimals(response.get("Items", []))
    medications = [
        {
            "rxId": item.get("rxId"),
            "medication": item.get("medication"),
            "dosage": item.get("dosage"),
            "adherencePercent": item.get("adherencePercent"),
            "status": item.get("status"),
            "lastRefillDate": item.get("lastRefillDate"),
            "daysSupply": item.get("daysSupply"),
            "refillsRemaining": item.get("refillsRemaining"),
        }
        for item in items
    ]
    return {"memberId": member_id, "medications": medications, "count": len(medications)}


def _get_member_claims(member_id):
    table = _source_table()
    response = table.query(
        KeyConditionExpression=(
            Key("memberId").eq(member_id)
            & Key("recordType").begins_with("CLAIM#")
        ),
    )
    items = _convert_decimals(response.get("Items", []))
    claims = [
        {
            "claimId": item.get("claimId"),
            "claimType": item.get("claimType"),
            "diagnosisCode": item.get("diagnosisCode"),
            "diagnosisDesc": item.get("diagnosisDesc"),
            "serviceDate": item.get("serviceDate"),
            "paidAmount": item.get("paidAmount"),
            "facilityName": item.get("facilityName"),
            "status": item.get("status"),
        }
        for item in items
    ]
    total_cost = sum(float(c.get("paidAmount", 0) or 0) for c in claims)
    return {"memberId": member_id, "claims": claims, "count": len(claims), "totalCost": total_cost}


def _get_member_care_events(member_id):
    table = _source_table()
    response = table.query(
        KeyConditionExpression=(
            Key("memberId").eq(member_id)
            & Key("recordType").begins_with("CARE_EVENT#")
        ),
    )
    items = _convert_decimals(response.get("Items", []))
    events = [
        {
            "eventId": item.get("eventId"),
            "eventType": item.get("eventType"),
            "facilityName": item.get("facilityName"),
            "date": item.get("date"),
            "diagnosisCode": item.get("diagnosisCode"),
            "outcome": item.get("outcome"),
            "notes": item.get("notes"),
        }
        for item in items
    ]
    events.sort(key=lambda e: e.get("date", ""), reverse=True)
    return {"memberId": member_id, "careEvents": events, "count": len(events)}
PYTHON
    filename = "handler.py"
  }
}
