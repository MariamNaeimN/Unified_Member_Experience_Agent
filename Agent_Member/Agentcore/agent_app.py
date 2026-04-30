"""
MemberXP Agent — Amazon Bedrock AgentCore Runtime
═══════════════════════════════════════════════════
Deploys the MemberXP NLP agent to AgentCore Runtime using direct Bedrock
InvokeModelWithResponseStream + tool-use (converse API).

All member data is accessed via the MCP Tools REST API (API Gateway → Lambda → DynamoDB).

The agent supports:
  - Streaming responses via InvokeModelWithResponseStream
  - Tool-use loop (Bedrock converse API with function calling)
  - Conversation memory (tracks active member across turns via session)
  - 12 MCP tools: search, profile, conditions, medications, claims, care events,
    analysis, care gaps, interventions, notifications, high risk, all members

Deploy:
  agentcore configure -e agent_app.py -r us-east-1 --disable-memory
  agentcore deploy

Test:
  agentcore invoke '{"prompt": "Tell me about John Smith"}'
  agentcore invoke '{"prompt": "What are his conditions?"}'
"""

import json
import os
import re
import logging
import urllib.request
import urllib.error

import boto3
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from bedrock_agentcore.memory import MemoryClient

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ── Configuration ────────────────────────────────────────────────────────────

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
API_URL = os.environ.get(
    "AGENT_TOOLS_API_URL",
    "https://nhudn46lcj.execute-api.us-east-1.amazonaws.com/dev"
)
MEMORY_ID = os.environ.get("MEMORY_ID", "MemberXP_STM-tnlZQpCtPW")

bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)

# Memory client for STM
memory_client = None
if MEMORY_ID:
    try:
        memory_client = MemoryClient(region_name=AWS_REGION)
        logger.info("Memory client initialized: %s", MEMORY_ID)
    except Exception as e:
        logger.warning("Memory client init failed: %s", e)

# ── AgentCore App ────────────────────────────────────────────────────────────

app = BedrockAgentCoreApp()

# ── Per-session conversation state ───────────────────────────────────────────
# Maps session_id → {"history": [...], "active_member": {"memberId": ..., "name": ...}}
_sessions = {}


def _get_session(session_id):
    """Get or create session state."""
    if session_id not in _sessions:
        _sessions[session_id] = {
            "history": [],
            "active_member": {"memberId": None, "name": None},
        }
    return _sessions[session_id]


# ── API Client ───────────────────────────────────────────────────────────────

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
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8") if e.fp else str(e)
        return {"error": f"API error {e.code}: {error_body}"}
    except Exception as e:
        return {"error": f"Request failed: {str(e)}"}


# ── Tool wrappers ────────────────────────────────────────────────────────────

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


# ── Bedrock Tool Definitions ────────────────────────────────────────────────

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


# ── System Prompt ────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """Healthcare AI clinical assistant. Call tools to get member data.

MEMORY: Track current member. Use LAST discussed member for pronouns.

SPEED: Call FEWEST tools. All tools accept name or ID directly — skip search_member.

MEMBER ID RULE: Use EXACT memberId from tools (M-xxxxx). Never confuse with claim IDs (CLM-xxxxx).

STRICT DATA ACCURACY - NO HALLUCINATION:
- ONLY report data that is EXPLICITLY returned by tools
- NEVER invent, estimate, or assume values not in tool responses
- If data is not available, say "Not in records" — do NOT make up values
- NO fabricated lab values (A1C, glucose, blood pressure readings)
- NO fabricated percentages or calculations unless explicitly in data
- NO assumed appointment details unless in care events data

ALLOWED from tool data:
- Exact adherence % from medications tool
- Exact dollar amounts from claims tool
- Exact dates from any tool
- Exact diagnosis names and ICD codes from conditions tool
- Exact medication names and dosages from medications tool
- Risk score from profile tool
- Care event types and dates from care events tool

NOT ALLOWED (hallucination):
- Lab values (A1C, glucose, cholesterol) — NOT in our data
- Blood pressure readings — NOT in our data
- Calculated percentages not in tool response
- Assumed clinical details

RESPONSE FORMAT: Use markdown with **bold** headers and - bullets:

**Member: [Name] ([ID])**
- DOB: [exact date]
- Gender: [value] | Plan: [plan name]

**Conditions** (from tool data only)
- [Diagnosis] ([ICD]) — [severity]

**Medications** (from tool data only)
- [Med] [dose] — [adherence]% adherence, [status]

**Claims Summary** (from tool data only)
- [count] claims, $[total] total

Be concise. Only state facts from tool responses."""


# ── Tool Execution ───────────────────────────────────────────────────────────

def execute_tool(tool_name, tool_input, active_member):
    """Execute a tool and update active member tracking."""
    fn = TOOL_MAP.get(tool_name)
    if not fn:
        return {"error": f"Unknown tool: {tool_name}"}, active_member

    # Route arguments
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

    # Track active member from tool results
    if isinstance(result, dict):
        if tool_name == "search_member" and result.get("members"):
            m = result["members"][0]
            active_member["memberId"] = m.get("memberId")
            active_member["name"] = (m.get("firstName", "") + " " + m.get("lastName", "")).strip()
            logger.info("Active member: %s (%s)", active_member["name"], active_member["memberId"])
        elif result.get("memberId") and not result.get("error"):
            mid = result["memberId"]
            if mid != active_member.get("memberId"):
                active_member["memberId"] = mid
                member_data = result.get("member", {})
                if member_data:
                    active_member["name"] = (member_data.get("firstName", "") + " " + member_data.get("lastName", "")).strip()
                elif not active_member.get("name"):
                    active_member["name"] = mid
                logger.info("Active member: %s (%s)", active_member["name"], active_member["memberId"])

    return result, active_member


# ── Streaming Agent Loop ────────────────────────────────────────────────────

def run_agent_streaming(user_question, session_state):
    """
    Run the agent with Bedrock converse API + tool-use loop.
    Uses InvokeModelWithResponseStream for streaming.
    Yields text chunks as they arrive.
    Returns the full text at the end.
    """
    history = session_state["history"]
    active_member = session_state["active_member"]

    # Inject active member context for follow-up questions
    msg_lower = user_question.lower().strip()
    pronoun_words = ["his", "her", "their", "them", "this member", "that patient", "the member", "the patient"]
    has_member_ref = bool(re.search(r"M-\d{5}", user_question, re.IGNORECASE))
    has_pronoun = any(p in msg_lower for p in pronoun_words)
    is_followup = not has_member_ref and (
        has_pronoun
        or msg_lower.startswith("what")
        or msg_lower.startswith("how")
        or msg_lower.startswith("show")
        or msg_lower.startswith("and ")
        or msg_lower.startswith("also")
    )

    if is_followup and active_member["memberId"] and not has_member_ref:
        context_hint = (
            f"[Context: The user is asking about {active_member['name'] or active_member['memberId']} "
            f"(ID: {active_member['memberId']}). Use this member ID for tool calls.]\n\n{user_question}"
        )
        history.append({"role": "user", "content": [{"text": context_hint}]})
    else:
        history.append({"role": "user", "content": [{"text": user_question}]})

    full_text = ""

    for iteration in range(3):  # max 3 tool-use rounds
        # ── Use converse_stream for streaming response ──
        response = bedrock.converse_stream(
            modelId=BEDROCK_MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=history,
            toolConfig={"tools": BEDROCK_TOOLS},
            inferenceConfig={
                "maxTokens": 1024,
                "temperature": 0.0,
            },
        )

        # Collect the streamed response
        assistant_content = []
        current_text = ""
        current_tool_use = None
        tool_use_input_json = ""
        stop_reason = ""

        for event in response["stream"]:
            # Content block start
            if "contentBlockStart" in event:
                start = event["contentBlockStart"].get("start", {})
                if "toolUse" in start:
                    # Starting a tool use block
                    current_tool_use = {
                        "toolUseId": start["toolUse"]["toolUseId"],
                        "name": start["toolUse"]["name"],
                    }
                    tool_use_input_json = ""

            # Content block delta
            elif "contentBlockDelta" in event:
                delta = event["contentBlockDelta"].get("delta", {})
                if "text" in delta:
                    text_chunk = delta["text"]
                    current_text += text_chunk
                    full_text += text_chunk
                    yield {"type": "chunk", "content": text_chunk}
                elif "toolUse" in delta:
                    tool_use_input_json += delta["toolUse"].get("input", "")

            # Content block stop
            elif "contentBlockStop" in event:
                if current_tool_use is not None:
                    # Parse tool input
                    try:
                        tool_input = json.loads(tool_use_input_json) if tool_use_input_json else {}
                    except json.JSONDecodeError:
                        tool_input = {}
                    current_tool_use["input"] = tool_input
                    assistant_content.append({"toolUse": current_tool_use})
                    current_tool_use = None
                    tool_use_input_json = ""
                elif current_text:
                    assistant_content.append({"text": current_text})
                    current_text = ""

            # Message stop
            elif "messageStop" in event:
                stop_reason = event["messageStop"].get("stopReason", "")

        # Add assistant message to history
        history.append({"role": "assistant", "content": assistant_content})

        # If the model wants to use tools
        if stop_reason == "tool_use":
            tool_results = []
            for block in assistant_content:
                if "toolUse" in block:
                    tool_use = block["toolUse"]
                    tool_name = tool_use["name"]
                    tool_input = tool_use.get("input", {})
                    tool_id = tool_use["toolUseId"]

                    logger.info("Tool call: %s(%s)", tool_name, json.dumps(tool_input, default=str))
                    yield {"type": "tool_use", "tool": tool_name, "input": tool_input}

                    result, active_member = execute_tool(tool_name, tool_input, active_member)
                    session_state["active_member"] = active_member

                    tool_results.append({
                        "toolResult": {
                            "toolUseId": tool_id,
                            "content": [{"json": result}],
                        }
                    })

            history.append({"role": "user", "content": tool_results})
            continue

        # Final response — done
        break

    yield {"type": "done", "full_text": full_text}


# ── Non-streaming fallback (for simple invoke) ──────────────────────────────

def run_agent_sync(user_question, session_state):
    """Run agent and return full text (non-streaming)."""
    full_text = ""
    for event in run_agent_streaming(user_question, session_state):
        if event["type"] == "chunk":
            full_text += event["content"]
        elif event["type"] == "done":
            full_text = event.get("full_text", full_text)
    return full_text


# ── AgentCore Entrypoint (single, streaming) ─────────────────────────────────

@app.entrypoint
def invoke(payload, context=None):
    """
    AgentCore Runtime entrypoint — streaming with STM memory.
    Loads last conversation turns from AgentCore Memory before each call.
    Saves the user message and agent response after each call.
    """
    user_message = payload.get("prompt", "Hello! How can I help you today?")

    # Extract session ID from context
    session_id = "default"
    if context:
        if hasattr(context, "session_id"):
            session_id = context.session_id
        elif hasattr(context, "runtime_session_id"):
            session_id = context.runtime_session_id
        elif isinstance(context, dict):
            session_id = context.get("session_id", context.get("runtimeSessionId", "default"))

    logger.info("Invoke: session=%s, memory=%s, prompt=%s", session_id, MEMORY_ID, user_message[:80])

    session_state = _get_session(session_id)

    # ── Load conversation history from STM ──
    if memory_client and MEMORY_ID:
        try:
            turns = memory_client.get_last_k_turns(
                memory_id=MEMORY_ID,
                actor_id="user",
                session_id=session_id,
                k=2,
            )
            if turns:
                # Inject prior conversation into system prompt context
                prior = []
                for turn in turns:
                    for msg in turn:
                        role = msg.get("role", "")
                        text = msg.get("content", {}).get("text", "")
                        if role and text:
                            prior.append(f"{role}: {text[:200]}")
                if prior:
                    context_str = "\n".join(prior[-3:])
                    # Add to history so the model sees prior conversation
                    if not session_state["history"]:
                        session_state["history"].append({
                            "role": "user",
                            "content": [{"text": f"[Previous conversation context]\n{context_str}"}]
                        })
                        session_state["history"].append({
                            "role": "assistant",
                            "content": [{"text": "I remember our previous conversation. How can I help?"}]
                        })
                logger.info("Loaded %d turns from STM", len(turns))
        except Exception as e:
            logger.warning("STM load failed: %s", e)

    # ── Stream the response ──
    full_response = ""
    for event in run_agent_streaming(user_message, session_state):
        if event.get("type") == "chunk":
            full_response += event.get("content", "")
        yield json.dumps(event) + "\n"

    # ── Save to STM ──
    if memory_client and MEMORY_ID and full_response:
        try:
            memory_client.create_event(
                memory_id=MEMORY_ID,
                actor_id="user",
                session_id=session_id,
                messages=[
                    (user_message, "user"),
                    (full_response[:500], "assistant"),
                ],
            )
            logger.info("Saved turn to STM: session=%s", session_id)
        except Exception as e:
            logger.warning("STM save failed: %s", e)


# ── Local run ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    # When running locally, also support interactive CLI mode
    import sys

    if "--cli" in sys.argv:
        print(f"\n🏥 MemberXP Agent (AgentCore + InvokeModelWithResponseStream)")
        print(f"   API: {API_URL}")
        print(f"   Model: {BEDROCK_MODEL_ID}\n")
        print("   Type 'quit' to exit, 'reset' to clear memory.\n")

        session = _get_session("cli")

        while True:
            try:
                active = session["active_member"]
                ctx = f" [{active['name'] or active['memberId']}]" if active["memberId"] else ""
                question = input(f"💬 You{ctx}: ").strip()
                if not question or question.lower() in ("quit", "exit", "q"):
                    break
                if question.lower() == "reset":
                    _sessions.pop("cli", None)
                    session = _get_session("cli")
                    print("  🔄 Reset.\n")
                    continue

                print()
                for event in run_agent_streaming(question, session):
                    if event["type"] == "chunk":
                        print(event["content"], end="", flush=True)
                    elif event["type"] == "tool_use":
                        print(f"\n  🔧 {event['tool']}({json.dumps(event['input'], default=str)})")
                    elif event["type"] == "done":
                        print("\n")
            except (KeyboardInterrupt, EOFError):
                break

        print("\nGoodbye!")
    else:
        app.run()
