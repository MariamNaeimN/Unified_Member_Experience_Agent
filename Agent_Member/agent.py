"""
MemberXP NLP Agent
──────────────────
A conversational agent that understands natural language questions about members
and calls MCP tools via the REST API to retrieve data.

Uses Amazon Bedrock Claude as the reasoning engine with tool-use (function calling).
All data access goes through the Agent Tools API (API Gateway → Lambda → DynamoDB).

Usage:
  python agent.py "What are the care gaps for John Smith?"
  python agent.py "Show me all high risk members"
  python agent.py  # interactive mode

Environment:
  AGENT_TOOLS_API_URL  — Base URL of the Agent Tools API (default: auto-detected)
  BEDROCK_MODEL_ID     — Bedrock model (default: anthropic.claude-3-haiku-20240307-v1:0)
  AWS_REGION           — AWS region (default: us-east-1)
"""

import json
import os
import re
import sys
import urllib.request
import urllib.error

import boto3

# ── Configuration ────────────────────────────────────────────────────────────

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
API_URL = os.environ.get(
    "AGENT_TOOLS_API_URL",
    "https://nhudn46lcj.execute-api.us-east-1.amazonaws.com/dev"
)

bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)


# ── API Client — calls MCP tools via REST ────────────────────────────────────

def call_tool_api(tool_name, body=None):
    """Call an MCP tool via the REST API."""
    url = f"{API_URL}/tools/{tool_name}"

    if body:
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
    else:
        req = urllib.request.Request(url, method="GET")

    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8") if e.fp else str(e)
        return {"error": f"API error {e.code}: {error_body}"}
    except Exception as e:
        return {"error": f"Request failed: {str(e)}"}


# ── Tool wrappers (call API instead of DynamoDB) ─────────────────────────────

def search_member(query):
    return call_tool_api("search_member", {"query": query})

def get_member_analysis(memberId):
    return call_tool_api("get_member_analysis", {"memberId": memberId})

def get_member_care_gaps(memberId):
    return call_tool_api("get_member_care_gaps", {"memberId": memberId})

def get_member_interventions(memberId):
    return call_tool_api("get_member_interventions", {"memberId": memberId})

def get_member_profile(memberId):
    return call_tool_api("get_member_profile", {"memberId": memberId})

def get_member_conditions(memberId):
    return call_tool_api("get_member_conditions", {"memberId": memberId})

def get_member_medications(memberId):
    return call_tool_api("get_member_medications", {"memberId": memberId})

def get_member_claims(memberId):
    return call_tool_api("get_member_claims", {"memberId": memberId})

def get_member_care_events(memberId):
    return call_tool_api("get_member_care_events", {"memberId": memberId})

def get_all_members_summary():
    return call_tool_api("get_all_members_summary")

def get_high_risk_members(min_risk_score=80):
    return call_tool_api("get_high_risk_members", {"min_risk_score": min_risk_score})

def get_member_notifications(memberId=None):
    body = {"memberId": memberId} if memberId else {}
    return call_tool_api("get_member_notifications", body)


# ── Tool registry for Bedrock ────────────────────────────────────────────────

TOOL_MAP = {
    "search_member": search_member,
    "get_member_analysis": get_member_analysis,
    "get_member_care_gaps": get_member_care_gaps,
    "get_member_interventions": get_member_interventions,
    "get_member_profile": get_member_profile,
    "get_member_conditions": get_member_conditions,
    "get_member_medications": get_member_medications,
    "get_member_claims": get_member_claims,
    "get_member_care_events": get_member_care_events,
    "get_all_members_summary": get_all_members_summary,
    "get_high_risk_members": get_high_risk_members,
    "get_member_notifications": get_member_notifications,
}

BEDROCK_TOOLS = [
    {"toolSpec": {"name": "search_member", "description": "Search for a member by name or ID. Use this first if the user mentions a member name.", "inputSchema": {"json": {"type": "object", "properties": {"query": {"type": "string", "description": "Name or member ID, e.g. 'John Smith' or 'M-10042'"}}, "required": ["query"]}}}},
    {"toolSpec": {"name": "get_member_analysis", "description": "Get the latest AI clinical analysis for a member including risk assessment, insights, and talking points", "inputSchema": {"json": {"type": "object", "properties": {"memberId": {"type": "string", "description": "Member ID or name"}}, "required": ["memberId"]}}}},
    {"toolSpec": {"name": "get_member_care_gaps", "description": "List open care gaps for a member with priority, protocol, and due date", "inputSchema": {"json": {"type": "object", "properties": {"memberId": {"type": "string", "description": "Member ID or name"}}, "required": ["memberId"]}}}},
    {"toolSpec": {"name": "get_member_interventions", "description": "List triggered workflow actions (SMS, TASK, ALERT, REFERRAL) for a member", "inputSchema": {"json": {"type": "object", "properties": {"memberId": {"type": "string", "description": "Member ID or name"}}, "required": ["memberId"]}}}},
    {"toolSpec": {"name": "get_member_profile", "description": "Get member demographics, plan info, and clinical data (risk score, BMI, allergies, smoking status)", "inputSchema": {"json": {"type": "object", "properties": {"memberId": {"type": "string", "description": "Member ID or name"}}, "required": ["memberId"]}}}},
    {"toolSpec": {"name": "get_member_conditions", "description": "Get active medical conditions/diagnoses with ICD-10 codes and severity", "inputSchema": {"json": {"type": "object", "properties": {"memberId": {"type": "string", "description": "Member ID or name"}}, "required": ["memberId"]}}}},
    {"toolSpec": {"name": "get_member_medications", "description": "Get current medications with adherence percentage and refill status", "inputSchema": {"json": {"type": "object", "properties": {"memberId": {"type": "string", "description": "Member ID or name"}}, "required": ["memberId"]}}}},
    {"toolSpec": {"name": "get_member_claims", "description": "Get claims history with costs, diagnosis, claim type, and dates", "inputSchema": {"json": {"type": "object", "properties": {"memberId": {"type": "string", "description": "Member ID or name"}}, "required": ["memberId"]}}}},
    {"toolSpec": {"name": "get_member_care_events", "description": "Get care events including visits, ER, hospitalizations, and missed appointments", "inputSchema": {"json": {"type": "object", "properties": {"memberId": {"type": "string", "description": "Member ID or name"}}, "required": ["memberId"]}}}},
    {"toolSpec": {"name": "get_all_members_summary", "description": "Get a summary list of all members with their risk scores. Use for questions about all members or population overview.", "inputSchema": {"json": {"type": "object", "properties": {}}}}},
    {"toolSpec": {"name": "get_high_risk_members", "description": "Get members with risk score above a threshold. Default threshold is 80.", "inputSchema": {"json": {"type": "object", "properties": {"min_risk_score": {"type": "integer", "description": "Minimum risk score threshold (default 80)"}}}}}},
    {"toolSpec": {"name": "get_member_notifications", "description": "Get notifications/alerts generated from AI analysis. Optionally filter by member.", "inputSchema": {"json": {"type": "object", "properties": {"memberId": {"type": "string", "description": "Optional: Member ID or name to filter"}}}}}},
]

SYSTEM_PROMPT = """You are a healthcare AI assistant for care managers. You retrieve member health data by calling tools that access the MCP API.

CONVERSATION MEMORY — CRITICAL:
- You MUST track which member the user is currently discussing across the conversation.
- When the user says "his", "her", "their", "this member", "that patient", "them", or asks a follow-up without naming a member, ALWAYS use the LAST member discussed.
- Example flow:
  User: "Tell me about John Smith" → you search for John Smith, get memberId M-10042
  User: "What are his conditions?" → you call get_member_conditions with memberId "M-10042" (NOT ask who)
  User: "And his medications?" → you call get_member_medications with memberId "M-10042"
  User: "What about the next steps?" → you call get_member_analysis with memberId "M-10042"
- NEVER ask "which member do you mean?" if there was a member discussed earlier in the conversation.
- If the user switches to a new member by name/ID, update your tracking to the new member.

Rules:
- When a user asks about a member by name or ID, call the appropriate tool directly (tools support both name and ID lookup).
- Always cite exact data: specific numbers, dates, medication names, adherence percentages, dollar amounts.
- Be concise and clinical. Use bullet points for lists.
- If multiple tools are needed, call them in sequence.
- For questions like "tell me about X", call get_member_profile first, then get_member_analysis.
- For questions about "all members" or "population", use get_all_members_summary or get_high_risk_members.
- For follow-up questions like "what are the next steps", "what should we do", call get_member_analysis and get_member_interventions for the current member.
- Never make up data. Only report what the tools return."""


# ── Agent loop ───────────────────────────────────────────────────────────────

# Track the active member across conversation turns
_active_member = {"memberId": None, "name": None}


def run_agent(user_question, conversation_history=None):
    """Run the agent with tool-use loop until a final answer is produced."""
    global _active_member

    if conversation_history is None:
        conversation_history = []

    # If the user's question uses pronouns or has no member reference,
    # inject the active member context so the model knows who we're talking about
    msg_lower = user_question.lower().strip()
    pronoun_words = ["his", "her", "their", "them", "this member", "that patient", "the member", "the patient"]
    has_member_ref = bool(re.search(r"M-\d{5}", user_question, re.IGNORECASE))
    has_name = any(c.isalpha() and len(user_question.split()) >= 2 for c in user_question[:1])
    has_pronoun = any(p in msg_lower for p in pronoun_words)
    is_followup = not has_member_ref and (has_pronoun or msg_lower.startswith("what") or msg_lower.startswith("how") or msg_lower.startswith("show") or msg_lower.startswith("and ") or msg_lower.startswith("also"))

    if is_followup and _active_member["memberId"] and not has_member_ref:
        # Inject context about the active member
        context_hint = f"[Context: The user is asking about {_active_member['name'] or _active_member['memberId']} (ID: {_active_member['memberId']}). Use this member ID for tool calls.]\n\n{user_question}"
        conversation_history.append({"role": "user", "content": [{"text": context_hint}]})
    else:
        conversation_history.append({"role": "user", "content": [{"text": user_question}]})

    for iteration in range(6):  # max 6 tool-use rounds
        response = bedrock.converse(
            modelId=BEDROCK_MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=conversation_history,
            toolConfig={"tools": BEDROCK_TOOLS},
        )

        output = response["output"]["message"]
        conversation_history.append(output)
        stop_reason = response.get("stopReason", "")

        # If the model wants to use tools
        if stop_reason == "tool_use":
            tool_results = []
            for block in output.get("content", []):
                if block.get("toolUse"):
                    tool_use = block["toolUse"]
                    tool_name = tool_use["name"]
                    tool_input = tool_use.get("input", {})
                    tool_id = tool_use["toolUseId"]

                    print(f"  🔧 {tool_name}({json.dumps(tool_input, default=str)})")

                    # Call the tool via API
                    fn = TOOL_MAP.get(tool_name)
                    if fn:
                        if tool_name == "get_all_members_summary":
                            result = fn()
                        elif tool_name == "get_high_risk_members":
                            result = fn(tool_input.get("min_risk_score", 80))
                        elif tool_name == "search_member":
                            result = fn(tool_input.get("query", ""))
                        elif tool_name == "get_member_notifications":
                            result = fn(tool_input.get("memberId"))
                        else:
                            result = fn(tool_input.get("memberId", ""))
                    else:
                        result = {"error": f"Unknown tool: {tool_name}"}

                    # Track active member from tool results
                    if isinstance(result, dict):
                        # From search_member — pick the first match
                        if tool_name == "search_member" and result.get("members"):
                            m = result["members"][0]
                            _active_member["memberId"] = m.get("memberId")
                            _active_member["name"] = (m.get("firstName", "") + " " + m.get("lastName", "")).strip()
                            print(f"  📌 Active member: {_active_member['name']} ({_active_member['memberId']})")
                        # From profile or any tool that returns memberId
                        elif result.get("memberId") and not result.get("error"):
                            mid = result["memberId"]
                            if mid != _active_member.get("memberId"):
                                _active_member["memberId"] = mid
                                # Try to get name from profile data
                                member_data = result.get("member", {})
                                if member_data:
                                    _active_member["name"] = (member_data.get("firstName", "") + " " + member_data.get("lastName", "")).strip()
                                elif not _active_member.get("name"):
                                    _active_member["name"] = mid
                                print(f"  📌 Active member: {_active_member['name']} ({_active_member['memberId']})")

                    tool_results.append({
                        "toolResult": {
                            "toolUseId": tool_id,
                            "content": [{"json": result}],
                        }
                    })

            conversation_history.append({"role": "user", "content": tool_results})
            continue

        # Final text response
        for block in output.get("content", []):
            if block.get("text"):
                return block["text"], conversation_history

    return "I wasn't able to find an answer after multiple attempts.", conversation_history


# ── CLI ──────────────────────────────────────────────────────────────────────

def main():
    print(f"\n🏥 MemberXP Agent (via MCP API: {API_URL})")

    if len(sys.argv) > 1:
        question = " ".join(sys.argv[1:])
        print(f"\n💬 {question}\n")
        answer, _ = run_agent(question)
        print(f"\n🤖 {answer}\n")
        return

    print("   Ask about any member by name or ID. Type 'quit' to exit.\n")
    print("   Examples:")
    print("     💬 Tell me about John Smith")
    print("     💬 What are his conditions?")
    print("     💬 And his medications?")
    print("     💬 What are the next steps?")
    print("   Type 'reset' to clear conversation memory.\n")
    history = []

    while True:
        try:
            # Show active member context
            if _active_member["memberId"]:
                prompt_ctx = f" [{_active_member['name'] or _active_member['memberId']}]"
            else:
                prompt_ctx = ""
            question = input(f"💬 You{prompt_ctx}: ").strip()
            if not question or question.lower() in ("quit", "exit", "q"):
                break
            if question.lower() == "reset":
                history = []
                _active_member["memberId"] = None
                _active_member["name"] = None
                print("  🔄 Conversation reset. Ask about a new member.\n")
                continue
            answer, history = run_agent(question, history)
            print(f"\n🤖 Agent: {answer}\n")
        except (KeyboardInterrupt, EOFError):
            break

    print("\nGoodbye!")


if __name__ == "__main__":
    main()
