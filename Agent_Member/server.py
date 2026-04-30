"""
MemberXP Agent MCP Server
─────────────────────────
Exposes the agent-output DynamoDB table as MCP tools so that AI assistants
can query member analysis data, care gaps, interventions, and notifications.

Transport: stdio (standard for MCP)
"""

import asyncio
import json
import logging
import os
from decimal import Decimal
from typing import Any

import boto3
from boto3.dynamodb.conditions import Key
from mcp.server import Server
from mcp.server.stdio import stdio_server
import mcp.types as types

# ── Configuration ────────────────────────────────────────────────────────────

AGENT_TABLE_NAME = os.environ.get(
    "DYNAMODB_AGENT_TABLE_NAME",
    "member-experience-agent-output-dev",
)
SOURCE_TABLE_NAME = os.environ.get(
    "DYNAMODB_SOURCE_TABLE_NAME",
    "member-experience-unified-profile-dev",
)
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("memberxp-mcp")

# ── DynamoDB helpers ─────────────────────────────────────────────────────────

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)


def _agent_table():
    return dynamodb.Table(AGENT_TABLE_NAME)


def _source_table():
    return dynamodb.Table(SOURCE_TABLE_NAME)


def _convert_decimals(obj: Any) -> Any:
    """Recursively convert DynamoDB Decimal values to int/float."""
    if isinstance(obj, list):
        return [_convert_decimals(i) for i in obj]
    if isinstance(obj, dict):
        return {k: _convert_decimals(v) for k, v in obj.items()}
    if isinstance(obj, Decimal):
        return int(obj) if obj == int(obj) else float(obj)
    return obj


def _safe_str(val: Any, default: str = "") -> str:
    """Return a string representation, falling back to *default*."""
    if val is None:
        return default
    return str(val)


def _resolve_member_id(identifier: str) -> str | None:
    """
    Resolve a member identifier to a memberId.
    Accepts either a member ID (e.g. "M-10042") or a name (e.g. "John Smith").
    Returns the memberId or None if not found.
    """
    import re
    # If it looks like a member ID, return as-is
    if re.match(r"M-\d+", identifier.strip(), re.IGNORECASE):
        return identifier.strip().upper()

    # Otherwise search by name in the source table
    table = _source_table()
    search_lower = identifier.strip().lower()

    query_params: dict[str, Any] = {
        "IndexName": "recordType-index",
        "KeyConditionExpression": Key("gsiRecordType").eq("MEMBER"),
    }
    while True:
        response = table.query(**query_params)
        for item in response.get("Items", []):
            full_name = (
                _safe_str(item.get("firstName")) + " " + _safe_str(item.get("lastName"))
            ).strip().lower()
            first = _safe_str(item.get("firstName")).lower()
            last = _safe_str(item.get("lastName")).lower()
            if (
                search_lower == full_name
                or search_lower == first
                or search_lower == last
                or search_lower in full_name
            ):
                return item.get("memberId")
        if "LastEvaluatedKey" not in response:
            break
        query_params["ExclusiveStartKey"] = response["LastEvaluatedKey"]

    return None


# ── MCP Server ───────────────────────────────────────────────────────────────

app = Server("memberxp-agent")


# ── Tool definitions ─────────────────────────────────────────────────────────

@app.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="search_member",
            description=(
                "Search for a member by name or ID. "
                "Accepts partial names (e.g. 'John', 'Smith', 'John Smith') or member IDs (e.g. 'M-10042'). "
                "Returns matching member details including memberId, name, plan, and risk score."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": 'Name or member ID to search for, e.g. "John Smith" or "M-10042"',
                    }
                },
                "required": ["query"],
            },
        ),
        types.Tool(
            name="get_member_analysis",
            description=(
                "Retrieve the latest AI analysis for a health-plan member. "
                "Accepts member ID (e.g. 'M-10042') or name (e.g. 'John Smith'). "
                "Returns risk assessment, claims insight, care history insight, "
                "medication insight, confidence score, and talking points."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "memberId": {
                        "type": "string",
                        "description": 'Member ID or name, e.g. "M-10042" or "John Smith"',
                    }
                },
                "required": ["memberId"],
            },
        ),
        types.Tool(
            name="get_member_care_gaps",
            description=(
                "List open care gaps identified for a member. "
                "Accepts member ID (e.g. 'M-10042') or name (e.g. 'John Smith'). "
                "Each gap includes type, priority, clinical protocol, due-within window, and status."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "memberId": {
                        "type": "string",
                        "description": 'Member ID or name, e.g. "M-10042" or "John Smith"',
                    }
                },
                "required": ["memberId"],
            },
        ),
        types.Tool(
            name="get_member_interventions",
            description=(
                "List recommended interventions for a member. "
                "Accepts member ID (e.g. 'M-10042') or name (e.g. 'John Smith'). "
                "Each intervention includes type, target, message, linked care gap, and status."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "memberId": {
                        "type": "string",
                        "description": 'Member ID or name, e.g. "M-10042" or "John Smith"',
                    }
                },
                "required": ["memberId"],
            },
        ),
        types.Tool(
            name="get_all_members_summary",
            description=(
                "Return a summary list of every member in the system. "
                "Includes memberId, first/last name, plan name, and risk score."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="get_member_notifications",
            description=(
                "Retrieve notifications generated from AI analysis sessions. "
                "Optionally filter by a single member."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "memberId": {
                        "type": "string",
                        "description": 'Optional member ID to filter notifications, e.g. "M-10042"',
                    }
                },
            },
        ),
        types.Tool(
            name="get_high_risk_members",
            description=(
                "Return members whose risk score meets or exceeds a threshold. "
                "Defaults to risk score >= 80."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "min_risk_score": {
                        "type": "integer",
                        "description": "Minimum risk score threshold (default 80)",
                        "default": 80,
                    }
                },
            },
        ),
        types.Tool(
            name="get_member_profile",
            description=(
                "Get the full member profile including demographics, patient clinical data, "
                "and enrollment information. Accepts member ID or name."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "memberId": {
                        "type": "string",
                        "description": 'Member ID or name, e.g. "M-10042" or "John Smith"',
                    }
                },
                "required": ["memberId"],
            },
        ),
        types.Tool(
            name="get_member_conditions",
            description=(
                "Get active medical conditions/diagnoses for a member. "
                "Includes diagnosis name, ICD-10 code, severity, and onset date. "
                "Accepts member ID or name."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "memberId": {
                        "type": "string",
                        "description": 'Member ID or name, e.g. "M-10042" or "John Smith"',
                    }
                },
                "required": ["memberId"],
            },
        ),
        types.Tool(
            name="get_member_medications",
            description=(
                "Get current medications for a member including adherence percentage and refill status. "
                "Accepts member ID or name."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "memberId": {
                        "type": "string",
                        "description": 'Member ID or name, e.g. "M-10042" or "John Smith"',
                    }
                },
                "required": ["memberId"],
            },
        ),
        types.Tool(
            name="get_member_claims",
            description=(
                "Get claims history for a member including claim type, diagnosis, cost, and date. "
                "Accepts member ID or name."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "memberId": {
                        "type": "string",
                        "description": 'Member ID or name, e.g. "M-10042" or "John Smith"',
                    }
                },
                "required": ["memberId"],
            },
        ),
        types.Tool(
            name="get_member_care_events",
            description=(
                "Get care events (visits, ER, hospitalizations, missed appointments) for a member. "
                "Accepts member ID or name."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "memberId": {
                        "type": "string",
                        "description": 'Member ID or name, e.g. "M-10042" or "John Smith"',
                    }
                },
                "required": ["memberId"],
            },
        ),
    ]


# ── Tool implementations ─────────────────────────────────────────────────────

@app.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
    try:
        if name == "search_member":
            result = _search_member(arguments["query"])
        elif name == "get_member_analysis":
            member_id = _resolve_member_id(arguments["memberId"])
            if not member_id:
                result = {"error": f"Member not found: {arguments['memberId']}"}
            else:
                result = _get_member_analysis(member_id)
        elif name == "get_member_care_gaps":
            member_id = _resolve_member_id(arguments["memberId"])
            if not member_id:
                result = {"error": f"Member not found: {arguments['memberId']}"}
            else:
                result = _get_member_care_gaps(member_id)
        elif name == "get_member_interventions":
            member_id = _resolve_member_id(arguments["memberId"])
            if not member_id:
                result = {"error": f"Member not found: {arguments['memberId']}"}
            else:
                result = _get_member_interventions(member_id)
        elif name == "get_all_members_summary":
            result = _get_all_members_summary()
        elif name == "get_member_notifications":
            mid = arguments.get("memberId")
            if mid:
                mid = _resolve_member_id(mid)
            result = _get_member_notifications(mid)
        elif name == "get_high_risk_members":
            result = _get_high_risk_members(arguments.get("min_risk_score", 80))
        elif name in ("get_member_profile", "get_member_conditions", "get_member_medications", "get_member_claims", "get_member_care_events"):
            member_id = _resolve_member_id(arguments["memberId"])
            if not member_id:
                result = {"error": f"Member not found: {arguments['memberId']}"}
            elif name == "get_member_profile":
                result = _get_member_profile(member_id)
            elif name == "get_member_conditions":
                result = _get_member_conditions(member_id)
            elif name == "get_member_medications":
                result = _get_member_medications(member_id)
            elif name == "get_member_claims":
                result = _get_member_claims(member_id)
            elif name == "get_member_care_events":
                result = _get_member_care_events(member_id)
        else:
            result = {"error": f"Unknown tool: {name}"}
    except Exception as exc:
        logger.exception("Tool %s failed", name)
        result = {"error": str(exc)}

    return [types.TextContent(type="text", text=json.dumps(result, default=str))]


# ── Query helpers ────────────────────────────────────────────────────────────

def _search_member(query: str) -> dict:
    """Search for members by name or ID. Returns all matches."""
    import re
    table = _source_table()
    search_lower = query.strip().lower()

    # If it looks like a member ID, do a direct lookup
    if re.match(r"M-\d+", query.strip(), re.IGNORECASE):
        mid = query.strip().upper()
        response = table.get_item(Key={"memberId": mid, "recordType": f"MEMBER#{mid}"})
        item = response.get("Item")
        if item:
            item = _convert_decimals(item)
            return {
                "members": [{
                    "memberId": item.get("memberId"),
                    "firstName": item.get("firstName"),
                    "lastName": item.get("lastName"),
                    "planName": item.get("planName"),
                    "riskScore": item.get("riskScore"),
                    "gender": item.get("gender"),
                    "dob": item.get("dob"),
                    "coverageStatus": item.get("coverageStatus"),
                }],
                "count": 1,
            }
        return {"members": [], "count": 0, "message": f"No member found with ID {mid}"}

    # Search by name
    matches = []
    query_params: dict[str, Any] = {
        "IndexName": "recordType-index",
        "KeyConditionExpression": Key("gsiRecordType").eq("MEMBER"),
    }
    while True:
        response = table.query(**query_params)
        for item in response.get("Items", []):
            item = _convert_decimals(item)
            full_name = (
                _safe_str(item.get("firstName")) + " " + _safe_str(item.get("lastName"))
            ).strip().lower()
            if search_lower in full_name:
                matches.append({
                    "memberId": item.get("memberId"),
                    "firstName": item.get("firstName"),
                    "lastName": item.get("lastName"),
                    "planName": item.get("planName"),
                    "riskScore": item.get("riskScore"),
                    "gender": item.get("gender"),
                    "dob": item.get("dob"),
                    "coverageStatus": item.get("coverageStatus"),
                })
        if "LastEvaluatedKey" not in response:
            break
        query_params["ExclusiveStartKey"] = response["LastEvaluatedKey"]

    return {"members": matches, "count": len(matches)}


def _get_member_analysis(member_id: str) -> dict:
    """Return the latest AI_DECISION record for *member_id*."""
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
        return {
            "memberId": member_id,
            "analysis": None,
            "message": "No analysis found for this member",
        }

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


def _get_member_care_gaps(member_id: str) -> dict:
    """Return all CARE_GAP records for *member_id*."""
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


def _get_member_interventions(member_id: str) -> dict:
    """Return all INTERVENTION records for *member_id*."""
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
    return {
        "memberId": member_id,
        "interventions": interventions,
        "count": len(interventions),
    }


def _get_all_members_summary() -> dict:
    """Query the source table GSI for all MEMBER records."""
    table = _source_table()
    members: list[dict] = []
    query_params: dict[str, Any] = {
        "IndexName": "recordType-index",
        "KeyConditionExpression": Key("gsiRecordType").eq("MEMBER"),
    }

    while True:
        response = table.query(**query_params)
        for item in response.get("Items", []):
            item = _convert_decimals(item)
            members.append(
                {
                    "memberId": item.get("memberId"),
                    "firstName": item.get("firstName"),
                    "lastName": item.get("lastName"),
                    "planName": item.get("planName"),
                    "riskScore": item.get("riskScore"),
                }
            )
        if "LastEvaluatedKey" not in response:
            break
        query_params["ExclusiveStartKey"] = response["LastEvaluatedKey"]

    return {"members": members, "count": len(members)}


def _get_member_notifications(member_id: str | None = None) -> dict:
    """Extract notifications from SESSION records."""
    table = _agent_table()
    notifications: list[dict] = []

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
        # Fetch SESSION records across all members via GSI
        session_items: list[dict] = []
        query_params: dict[str, Any] = {
            "IndexName": "recordType-index",
            "KeyConditionExpression": Key("gsiRecordType").eq("SESSION"),
        }
        while True:
            response = table.query(**query_params)
            session_items.extend(response.get("Items", []))
            if "LastEvaluatedKey" not in response or len(session_items) >= 500:
                break
            query_params["ExclusiveStartKey"] = response["LastEvaluatedKey"]

    seen_members: set[str] = set()
    for item in session_items:
        item = _convert_decimals(item)
        mid = item.get("memberId", "")
        # Deduplicate: keep only the latest session per member
        if mid in seen_members:
            continue
        seen_members.add(mid)

        for n in item.get("notifications", []):
            notifications.append(
                {
                    "memberId": mid,
                    "sessionId": item.get("sessionId"),
                    "type": n.get("type"),
                    "title": n.get("title"),
                    "message": n.get("message"),
                    "priority": n.get("priority"),
                    "status": n.get("status", "unread"),
                    "createdAt": _safe_str(item.get("updatedAt")),
                }
            )

    notifications.sort(key=lambda x: x.get("createdAt", ""), reverse=True)
    return {
        "notifications": notifications,
        "count": len(notifications),
        "unread": sum(1 for n in notifications if n.get("status") == "unread"),
    }


def _get_high_risk_members(min_risk_score: int = 80) -> dict:
    """Return members whose riskScore >= *min_risk_score*."""
    all_members = _get_all_members_summary()
    high_risk = [
        m
        for m in all_members["members"]
        if (m.get("riskScore") or 0) >= min_risk_score
    ]
    high_risk.sort(key=lambda m: m.get("riskScore", 0), reverse=True)
    return {
        "members": high_risk,
        "count": len(high_risk),
        "threshold": min_risk_score,
    }


def _get_member_profile(member_id: str) -> dict:
    """Get full member profile — demographics + patient clinical data."""
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


def _get_member_conditions(member_id: str) -> dict:
    """Get active conditions for a member."""
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


def _get_member_medications(member_id: str) -> dict:
    """Get current medications for a member."""
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


def _get_member_claims(member_id: str) -> dict:
    """Get claims history for a member."""
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


def _get_member_care_events(member_id: str) -> dict:
    """Get care events for a member."""
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


# ── Entrypoint ───────────────────────────────────────────────────────────────

async def main():
    async with stdio_server() as (read_stream, write_stream):
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options(),
        )


if __name__ == "__main__":
    asyncio.run(main())

