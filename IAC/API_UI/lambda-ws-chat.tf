# =============================================================================
# Lambda: ws-chat — Handles sendMessage route with Bedrock streaming
# Consolidates fetch-profile + analyze-profile + write-results into ONE Lambda
# Streams Bedrock response chunks back to client via Management API
# =============================================================================

resource "aws_cloudwatch_log_group" "ws_chat" {
  name              = "/aws/lambda/${var.project_name}-ws-chat-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "ws_chat" {
  function_name = "${var.project_name}-ws-chat-${var.environment}"
  description   = "WebSocket sendMessage handler: streams Bedrock AI responses to client"
  role          = aws_iam_role.ws_chat_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = 120
  memory_size   = 512

  filename         = data.archive_file.ws_chat.output_path
  source_code_hash = data.archive_file.ws_chat.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME       = var.dynamodb_table_name
      DYNAMODB_AGENT_TABLE_NAME = var.dynamodb_agent_table_name
      BEDROCK_MODEL_ID          = var.bedrock_model_id
      AGENTCORE_RUNTIME_ARN     = "arn:aws:bedrock-agentcore:us-east-1:193786182229:runtime/MemberX-08pzRLFY3Q"
    }
  }

  tags = {
    Name = "${var.project_name}-ws-chat"
    Role = "WebSocket Chat Streaming Handler"
  }

  depends_on = [aws_cloudwatch_log_group.ws_chat]
}

data "archive_file" "ws_chat" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-ws-chat.zip"

  source {
    content  = <<-PYTHON
import json
import os
import re
import logging
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
bedrock = boto3.client("bedrock-runtime")

TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
AGENT_TABLE_NAME = os.environ["DYNAMODB_AGENT_TABLE_NAME"]
MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
AGENTCORE_ARN = os.environ.get("AGENTCORE_RUNTIME_ARN", "")

CHUNK_THRESHOLD = 80

# AgentCore client — only init if ARN is set
agentcore_client = None
if AGENTCORE_ARN:
    try:
        agentcore_client = boto3.client("bedrock-agentcore")
    except Exception:
        logger.warning("bedrock-agentcore client not available")


def lambda_handler(event, context):
    """
    sendMessage route handler.
    Parses message, fetches profile, streams Bedrock response, writes SESSION record.
    """
    connection_id = event["requestContext"]["connectionId"]
    domain_name = event["requestContext"]["domainName"]
    stage = event["requestContext"]["stage"]
    endpoint_url = f"https://{domain_name}/{stage}"

    body = json.loads(event.get("body", "{}") or "{}")
    member_id = body.get("memberId", "")
    message = body.get("message", "")
    session_id = body.get("sessionId", "session-" + str(int(datetime.utcnow().timestamp())))
    mode = body.get("mode", "bedrock")

    logger.info("Chat request: connection=%s, member=%s, mode=%s", connection_id, member_id, mode)

    # Step 1: Verify authentication via CONNECTION# record
    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    conn_result = agent_table.get_item(
        Key={"memberId": f"CONNECTION#{connection_id}", "recordType": "META"}
    )
    connection_record = conn_result.get("Item")
    if not connection_record:
        send_to_connection(connection_id, endpoint_url, {"type": "error", "message": "Not authenticated"})
        return {"statusCode": 401}

    user_email = connection_record.get("userId", "unknown")

    # ── AgentCore mode ──
    if mode == "agentcore":
        return handle_agentcore(connection_id, endpoint_url, message, session_id)

    # Step 2: Validate memberId
    if not member_id:
        match = re.search(r"M-\d{5}", message)
        if match:
            member_id = match.group()
        else:
            send_to_connection(connection_id, endpoint_url, {"type": "error", "message": "memberId is required or include it in your message (e.g., M-10042)"})
            return {"statusCode": 200}

    # Step 3: Validate message length
    if len(message) > 2000:
        send_to_connection(connection_id, endpoint_url, {"type": "error", "message": "Message too long (max 2000 characters)"})
        return {"statusCode": 200}

    if not message:
        message = "Analyze member " + member_id

    # Step 4: Send status — fetching
    send_to_connection(connection_id, endpoint_url, {"type": "status", "stage": "fetching"})

    # Step 5: Fetch member profile (same logic as fetch-profile Lambda)
    profile = fetch_member_profile(member_id)
    if not profile:
        send_to_connection(connection_id, endpoint_url, {"type": "error", "message": f"Member not found: {member_id}"})
        return {"statusCode": 200}

    # Step 6: Fetch chat history
    chat_history = fetch_chat_history(member_id, limit=10)

    # Step 7: Send status — analyzing
    send_to_connection(connection_id, endpoint_url, {"type": "status", "stage": "analyzing"})

    # Step 8: Stream Bedrock response
    try:
        full_text = stream_bedrock_response(connection_id, endpoint_url, profile, chat_history, message)
    except Exception as e:
        logger.error("Bedrock error: %s", str(e))
        send_to_connection(connection_id, endpoint_url, {"type": "error", "message": "AI service temporarily unavailable. Please try again."})
        return {"statusCode": 200}

    # Step 9: Parse AI response
    ai_result = parse_ai_response(full_text, member_id)

    # Step 10: Write SESSION record
    write_result = write_session_record(member_id, session_id, message, full_text, ai_result)

    # Step 11: Send done message
    member = profile.get("member", {}) or {}
    member_name = (member.get("firstName", "") + " " + member.get("lastName", "")).strip()
    send_to_connection(connection_id, endpoint_url, {
        "type": "done",
        "meta": {
            "memberId": member_id,
            "memberName": member_name,
            "sessionId": session_id,
            "decisionId": write_result["decisionId"],
            "careGaps": write_result["careGaps"],
            "interventions": write_result["interventions"],
            "cached": False
        }
    })

    return {"statusCode": 200}


def handle_agentcore(connection_id, endpoint_url, message, session_id):
    """Handle AgentCore mode — call InvokeAgentRuntime and stream chunks to client in real-time."""
    if not agentcore_client or not AGENTCORE_ARN:
        send_to_connection(connection_id, endpoint_url, {"type": "error", "message": "AgentCore Runtime not configured."})
        return {"statusCode": 200}
    if not message:
        send_to_connection(connection_id, endpoint_url, {"type": "error", "message": "Message is required."})
        return {"statusCode": 200}

    send_to_connection(connection_id, endpoint_url, {"type": "status", "stage": "analyzing"})

    try:
        # ── Load active member from DynamoDB CONNECTION record ──
        agent_table = dynamodb.Table(AGENT_TABLE_NAME)
        active_member_id = None
        active_member_name = None
        try:
            conn_rec = agent_table.get_item(
                Key={"memberId": f"CONNECTION#{connection_id}", "recordType": "META"}
            ).get("Item", {})
            active_member_id = conn_rec.get("agentcoreMemberId")
            active_member_name = conn_rec.get("agentcoreMemberName")
        except Exception:
            pass

        # ── Detect if this is a follow-up (pronouns, no member name/ID) ──
        msg_lower = message.lower().strip()
        has_member_ref = bool(re.search(r"M-\d{5}", message, re.IGNORECASE))
        # Check if message contains a name (2+ capitalized words)
        has_name = bool(re.search(r"[A-Z][a-z]+ [A-Z][a-z]+", message))
        pronouns = ["his", "her", "their", "them", "this member", "that patient"]
        has_pronoun = any(p in msg_lower for p in pronouns)
        is_followup = not has_member_ref and not has_name and (
            has_pronoun or msg_lower.startswith("what") or msg_lower.startswith("how")
            or msg_lower.startswith("show") or msg_lower.startswith("and ")
        )

        # Inject member context for follow-ups
        prompt = message
        if is_followup and active_member_id:
            prompt = f"[The user is asking about {active_member_name or active_member_id} (ID: {active_member_id}). Use this member for tool calls.]\n\n{message}"
            logger.info("Injected member context: %s", active_member_id)

        payload = json.dumps({"prompt": prompt}).encode()
        if len(session_id) < 33:
            session_id = session_id + "-" + "0" * (33 - len(session_id) - 1)

        response = agentcore_client.invoke_agent_runtime(
            agentRuntimeArn=AGENTCORE_ARN,
            runtimeSessionId=session_id,
            payload=payload,
            qualifier="DEFAULT",
        )

        body = response.get("response")
        if body is None:
            send_to_connection(connection_id, endpoint_url, {"type": "error", "message": "Empty response from AgentCore."})
            return {"statusCode": 200}

        full_text = ""
        buf = ""

        # Read StreamingBody in small chunks for real-time streaming
        while True:
            raw = body.read(512)
            if not raw:
                break
            buf += raw.decode("utf-8")

            # Process every complete line as it arrives
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                text = _parse_agentcore_sse_line(line.strip())
                if text is not None:
                    full_text += text
                    send_to_connection(connection_id, endpoint_url, {"type": "chunk", "content": text})

        # Flush remaining buffer
        if buf.strip():
            text = _parse_agentcore_sse_line(buf.strip())
            if text is not None:
                full_text += text
                send_to_connection(connection_id, endpoint_url, {"type": "chunk", "content": text})

        # ── Extract and save active member from response ──
        # Look for member IDs or names in the response text
        member_match = re.search(r"(M-\d{5})", full_text)
        if member_match:
            new_mid = member_match.group(1)
            # Also try to extract name near the ID
            name_match = re.search(r"\*\*([A-Z][a-z]+ [A-Z][a-z]+)\*\*", full_text)
            new_name = name_match.group(1) if name_match else new_mid
            try:
                agent_table.update_item(
                    Key={"memberId": f"CONNECTION#{connection_id}", "recordType": "META"},
                    UpdateExpression="SET agentcoreMemberId = :mid, agentcoreMemberName = :mname",
                    ExpressionAttributeValues={":mid": new_mid, ":mname": new_name},
                )
                logger.info("Saved active member: %s (%s)", new_name, new_mid)
            except Exception as save_err:
                logger.warning("Failed to save active member: %s", save_err)
        elif has_member_ref:
            # User mentioned a member ID directly
            mid = re.search(r"M-\d{5}", message, re.IGNORECASE).group().upper()
            try:
                agent_table.update_item(
                    Key={"memberId": f"CONNECTION#{connection_id}", "recordType": "META"},
                    UpdateExpression="SET agentcoreMemberId = :mid",
                    ExpressionAttributeValues={":mid": mid},
                )
            except Exception:
                pass

        send_to_connection(connection_id, endpoint_url, {
            "type": "done",
            "meta": {"sessionId": session_id, "source": "agentcore", "cached": False}
        })

    except Exception as e:
        logger.error("AgentCore error: %s", str(e))
        send_to_connection(connection_id, endpoint_url, {"type": "error", "message": f"AgentCore error: {str(e)}"})

    return {"statusCode": 200}


def _parse_agentcore_sse_line(line):
    """Parse one SSE line from AgentCore. Returns text content or None. Skips tool_use events."""
    if not line or not line.startswith("data: "):
        return None
    data_str = line[6:].strip()
    try:
        inner = json.loads(data_str)
    except json.JSONDecodeError:
        return data_str

    if isinstance(inner, str):
        for part in inner.strip().split("\n"):
            part = part.strip()
            if not part:
                continue
            try:
                evt = json.loads(part)
                if evt.get("type") == "chunk":
                    return evt.get("content", "")
                # Skip tool_use — don't show to user
            except json.JSONDecodeError:
                return part
    elif isinstance(inner, dict):
        if inner.get("type") == "chunk":
            return inner.get("content", "")
        # Skip tool_use — don't show to user
    return None


def send_to_connection(connection_id, endpoint_url, message):
    """Send a JSON message to a WebSocket client via the Management API."""
    try:
        apigw = boto3.client("apigatewaymanagementapi", endpoint_url=endpoint_url)
        apigw.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(message).encode("utf-8")
        )
        return True
    except apigw.exceptions.GoneException:
        logger.warning("Connection gone: %s", connection_id)
        return False
    except Exception as e:
        logger.error("Error sending to connection %s: %s", connection_id, str(e))
        return False


def fetch_member_profile(member_id):
    """Query DynamoDB for the full unified profile of a member (BOTH source and agent tables)."""
    table = dynamodb.Table(TABLE_NAME)
    result = table.query(
        KeyConditionExpression=Key("memberId").eq(member_id)
    )
    items = result.get("Items", [])

    if not items:
        return None

    profile = {
        "member": None,
        "patient": None,
        "conditions": [],
        "claims": [],
        "pharmacy": [],
        "careEvents": [],
        "providers": []
    }

    for item in items:
        rt = item.get("recordType", "")
        if rt.startswith("MEMBER#"):
            profile["member"] = item
        elif rt.startswith("PATIENT#"):
            profile["patient"] = item
        elif rt.startswith("CONDITION#"):
            profile["conditions"].append(item)
        elif rt.startswith("CLAIM#"):
            profile["claims"].append(item)
        elif rt.startswith("PHARMACY#"):
            profile["pharmacy"].append(item)
        elif rt.startswith("CARE_EVENT#"):
            profile["careEvents"].append(item)
        elif rt.startswith("PROVIDER#"):
            profile["providers"].append(item)

    # Also fetch from agent table
    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    agent_result = agent_table.query(
        KeyConditionExpression=Key("memberId").eq(member_id)
    )
    for item in agent_result.get("Items", []):
        rt = item.get("recordType", "")
        if rt.startswith("PROVIDER#"):
            profile["providers"].append(item)

    if not profile["member"]:
        return None

    # Convert Decimals for JSON serialization
    profile = json.loads(json.dumps(profile, default=str))
    return profile


def fetch_chat_history(member_id, limit=10):
    """Query recent SESSION records for conversation context."""
    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    result = agent_table.query(
        KeyConditionExpression=Key("memberId").eq(member_id) & Key("recordType").begins_with("SESSION#"),
        ScanIndexForward=False,
        Limit=limit
    )
    sessions = result.get("Items", [])
    # Sort ascending by updatedAt
    sessions.sort(key=lambda x: x.get("updatedAt", ""))
    return [json.loads(json.dumps(s, default=str)) for s in sessions]


def stream_bedrock_response(connection_id, endpoint_url, profile, chat_history, user_message):
    """Call Bedrock streaming API and relay each chunk to the WebSocket client."""
    prompt = build_prompt(profile, chat_history, user_message)

    messages = []
    for ch in chat_history[-3:]:
        messages.append({"role": "user", "content": ch.get("userMessage", "")})
        messages.append({"role": "assistant", "content": ch.get("agentResponse", "")})
    messages.append({"role": "user", "content": prompt})

    response = bedrock.invoke_model_with_response_stream(
        modelId=MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 2048,
            "temperature": 0.2,
            "messages": messages
        })
    )

    full_text = ""
    chunk_buffer = ""

    for stream_event in response["body"]:
        chunk = json.loads(stream_event["chunk"]["bytes"])
        if chunk.get("type") == "content_block_delta":
            delta = chunk.get("delta", {})
            if delta.get("type") == "text_delta":
                text = delta.get("text", "")
                full_text += text
                chunk_buffer += text

                if len(chunk_buffer) >= CHUNK_THRESHOLD:
                    send_to_connection(connection_id, endpoint_url, {"type": "chunk", "content": chunk_buffer})
                    chunk_buffer = ""

    if chunk_buffer:
        send_to_connection(connection_id, endpoint_url, {"type": "chunk", "content": chunk_buffer})

    return full_text


def build_prompt(profile, chat_history=None, user_message=""):
    """Build the Bedrock prompt from member profile data.
    For initial analysis: returns structured JSON format.
    For follow-up questions: returns conversational response using prior analysis context.
    """
    member = profile.get("member", {}) or {}
    patient = profile.get("patient", {}) or {}
    conditions = profile.get("conditions", [])
    claims = profile.get("claims", [])
    pharmacy = profile.get("pharmacy", [])
    events = profile.get("careEvents", [])

    # Detect if this is a follow-up question (chat history exists for this member)
    is_followup = chat_history and len(chat_history) > 0

    # Check if the user message looks like an initial analysis request
    initial_keywords = ["tell me about", "analyze", "analysis", "what about", "check on", "review"]
    msg_lower = user_message.lower().strip()
    is_initial = any(kw in msg_lower for kw in initial_keywords) or not is_followup

    parts = []

    if is_initial:
        # Full analysis mode — structured JSON response
        parts.append("You are a healthcare AI clinical decision support chatbot. A care manager is asking you about a member.")
        parts.append("Respond conversationally but include structured clinical analysis.")
    else:
        # Follow-up mode — conversational response using context
        parts.append("You are a healthcare AI clinical decision support chatbot. A care manager is asking a follow-up question about a member.")
        parts.append("You have already analyzed this member. Use the conversation history and member data to answer their specific question.")
        parts.append("Respond conversationally in plain text. Be specific and helpful. Do NOT respond in JSON format.")

    parts.append("")
    if user_message:
        parts.append("Care manager asked: " + user_message)
        parts.append("")
    parts.append("Your job is to:")
    parts.append("1. ANALYZE claims, care history, conditions, and medications to build a complete clinical picture")
    parts.append("2. DETERMINE the next-best actions ranked by clinical urgency")
    parts.append("3. SPECIFY workflow triggers (SMS to patient, tasks for care team, alerts to pharmacy, referrals to specialists)")
    parts.append("")
    parts.append("Analyze the following member data thoroughly.")
    parts.append("")
    parts.append("MEMBER INFORMATION:")
    parts.append("- Name: " + member.get("firstName", "") + " " + member.get("lastName", ""))
    dob = member.get("dob", "")
    age_str = ""
    if dob:
        try:
            born = datetime.strptime(dob, "%Y-%m-%d")
            today = datetime.utcnow()
            age = today.year - born.year - ((today.month, today.day) < (born.month, born.day))
            age_str = str(age)
        except Exception:
            age_str = "unknown"
    parts.append("- Age: " + age_str + " years old")
    parts.append("- IMPORTANT: The member is exactly " + age_str + " years old. Do not say any other age.")
    parts.append("- Plan: " + member.get("planName", ""))
    parts.append("- Coverage: " + member.get("coverageStatus", ""))
    parts.append("")
    parts.append("PATIENT CLINICAL DATA:")
    parts.append("- Risk Score: " + str(patient.get("riskScore", "N/A")) + "/100")
    parts.append("- Living Situation: " + str(patient.get("livingSituation", "N/A")))
    parts.append("- Allergies: " + str(patient.get("allergies", "None")))
    parts.append("- BMI: " + str(patient.get("bmi", "N/A")))
    parts.append("- Smoking Status: " + str(patient.get("smokingStatus", "N/A")))
    parts.append("")
    parts.append("ACTIVE CONDITIONS:")
    if conditions:
        for c in conditions:
            parts.append("- " + c.get("diagnosis", "") + " (ICD: " + c.get("icdCode", "") + ", Severity: " + c.get("severity", "") + ", Since: " + c.get("onsetDate", "") + ")")
    else:
        parts.append("- No active conditions on record")
    parts.append("")

    parts.append("CLAIMS HISTORY (analyze patterns, frequency, cost trends, ER utilization):")
    sorted_claims = sorted(claims, key=lambda x: x.get("serviceDate", ""), reverse=True)[:10]
    if sorted_claims:
        total_cost = 0
        er_count = 0
        for cl in sorted_claims:
            cost = cl.get("paidAmount", "0")
            try:
                total_cost += float(cost)
            except (ValueError, TypeError):
                pass
            if cl.get("claimType") == "Emergency":
                er_count += 1
            parts.append("- " + cl.get("serviceDate", "") + ": " + cl.get("claimType", "") + " - " + cl.get("diagnosisDesc", "") + " ($" + str(cost) + ")")
        parts.append("CLAIMS SUMMARY: " + str(len(sorted_claims)) + " recent claims, " + str(er_count) + " ER visits, total cost $" + str(total_cost))
    else:
        parts.append("- No claims on record")
    parts.append("")

    parts.append("MEDICATION ADHERENCE (flag non-adherence below 80%, overdue refills, consider allergies):")
    if pharmacy:
        overdue_count = 0
        low_adherence_count = 0
        non_compliant_meds = []
        compliant_meds = []
        for rx in pharmacy:
            adherence = rx.get("adherencePercent", 0)
            try:
                adherence_val = int(adherence) if adherence else 0
            except (ValueError, TypeError):
                adherence_val = 0
            status = rx.get("status", "")
            if status == "Overdue":
                overdue_count += 1
            if adherence_val < 80:
                low_adherence_count += 1
                non_compliant_meds.append(rx.get("medication", "") + " (" + str(adherence_val) + "%)")
            else:
                compliant_meds.append(rx.get("medication", "") + " (" + str(adherence_val) + "%)")
            flags = []
            if status == "Overdue":
                flags.append("FLAGGED: OVERDUE REFILL")
            if adherence_val < 80:
                flags.append("FLAGGED: BELOW 80% THRESHOLD (" + str(adherence_val) + "%)")
            elif adherence_val >= 80:
                flags.append("OK: ABOVE 80% THRESHOLD (" + str(adherence_val) + "%)")
            flag_str = " | ".join(flags) if flags else "OK"
            parts.append("- " + rx.get("medication", "") + " " + rx.get("dosage", "") + ": Adherence " + str(adherence) + "%, Status: " + status + ", Last Refill: " + rx.get("lastRefillDate", "") + " [" + flag_str + "]")
        parts.append("MEDICATION SUMMARY: " + str(overdue_count) + " overdue refills, " + str(low_adherence_count) + " medications below 80% adherence threshold")
        if non_compliant_meds:
            parts.append("NON-COMPLIANT (below 80%): " + ", ".join(non_compliant_meds))
        if compliant_meds:
            parts.append("COMPLIANT (at or above 80%): " + ", ".join(compliant_meds))
        parts.append("CRITICAL RULE: ONLY " + str(low_adherence_count) + " medication(s) are below 80% adherence. Do NOT claim any medication is non-adherent unless it is listed in NON-COMPLIANT above. All medications in COMPLIANT are fine — never mention them as concerns.")
    else:
        parts.append("- No medications on record")
    parts.append("")

    providers = profile.get("providers", [])
    parts.append("CARE TEAM (member's providers — PCP, specialists, ER):")
    if providers:
        for prov in providers:
            rel = prov.get("relationship", "")
            parts.append("- " + prov.get("name", "") + " (" + rel + ") — " + prov.get("specialty", "") + " at " + prov.get("facilityName", "") + " | " + prov.get("phone", "") + " | In-Network: " + str(prov.get("inNetwork", "")))
    else:
        parts.append("- No provider records on file")
    parts.append("")

    parts.append("CARE HISTORY (analyze visit patterns, missed appointments, care engagement):")
    sorted_events = sorted(events, key=lambda x: x.get("date", ""), reverse=True)[:10]
    if sorted_events:
        missed_count = 0
        er_events = 0
        for ev in sorted_events:
            if ev.get("eventType") == "Missed_Appointment":
                missed_count += 1
            if ev.get("eventType") == "ER_Visit":
                er_events += 1
            parts.append("- " + ev.get("date", "") + ": " + ev.get("eventType", "") + " at " + ev.get("facilityName", "") + " - " + ev.get("outcome", ""))
            notes = ev.get("notes", "")
            if notes:
                parts.append("  Notes: " + str(notes)[:150])
        parts.append("CARE SUMMARY: " + str(missed_count) + " missed appointments, " + str(er_events) + " ER visits")
    else:
        parts.append("- No care events on record")
    parts.append("")

    parts.append("INSTRUCTIONS: Analyze data, identify care gaps, specify workflow actions (SMS/TASK/ALERT/REFERRAL), provide 3 talking points. Consider allergies and living situation.")
    parts.append("")

    if is_initial:
        parts.append('RESPOND IN THIS EXACT JSON FORMAT (be concise):')
        parts.append('{"analysis":"2-3 sentence summary","riskAssessment":"HIGH/MEDIUM/LOW with reason","claimsInsight":"1 sentence","careHistoryInsight":"1 sentence","medicationInsight":"1 sentence","careGaps":[{"type":"gap","priority":"CRITICAL/HIGH/MEDIUM/LOW","protocol":"name","dueWithin":"time"}],"recommendedInterventions":[{"type":"SMS/TASK/ALERT/REFERRAL","target":"who","message":"text","linkedGap":"gap","system":"system"}],"talkingPoints":["1","2","3"],"confidence":0.0}')
        parts.append("")
        parts.append("Respond ONLY with valid JSON. No markdown.")
    else:
        parts.append("Answer the care manager's question directly using the EXACT member data above.")
        parts.append("ALWAYS cite exact data: use specific medication names with dosages, exact adherence percentages, exact dollar amounts, specific dates (YYYY-MM-DD), provider full names, and facility names. Never paraphrase numbers — quote them exactly as they appear in the data.")
        parts.append("Example: Instead of 'medication adherence is low', say 'Lisinopril 20mg adherence is 72%, below the 80% threshold, refill overdue since 2026-03-25'.")
        parts.append("IMPORTANT: In follow-up mode you are ONLY providing recommendations. You are NOT triggering any actions. Do NOT say 'I will trigger', 'I will send', 'I will submit', or 'I have scheduled'. Instead say 'I recommend', 'you should', 'the care team should'. Only the initial analysis triggers real workflow actions.")
        parts.append("Do NOT respond in JSON format. Use plain text with clear paragraphs.")

    return "\n".join(parts)


def parse_ai_response(ai_text, member_id):
    """Parse the AI response text into a structured result dict."""
    try:
        text = ai_text.strip()
        if text.startswith("```"):
            lines = text.split("\n")
            json_lines = []
            inside = False
            for line in lines:
                if line.strip().startswith("```") and not inside:
                    inside = True
                    continue
                elif line.strip().startswith("```") and inside:
                    break
                elif inside:
                    json_lines.append(line)
            text = "\n".join(json_lines)
        result = json.loads(text)
    except json.JSONDecodeError:
        logger.warning("Failed to parse AI response as JSON")
        result = {
            "analysis": ai_text[:500],
            "riskAssessment": "UNKNOWN",
            "claimsInsight": "",
            "careHistoryInsight": "",
            "medicationInsight": "",
            "careGaps": [],
            "recommendedInterventions": [],
            "talkingPoints": [],
            "confidence": 0.5
        }

    result.setdefault("claimsInsight", "")
    result.setdefault("careHistoryInsight", "")
    result.setdefault("medicationInsight", "")
    result.setdefault("careGaps", [])
    result.setdefault("recommendedInterventions", [])
    result.setdefault("talkingPoints", [])

    result["memberId"] = member_id
    result["decisionId"] = "D-" + str(int(datetime.utcnow().timestamp()))
    result["model"] = MODEL_ID
    result["timestamp"] = datetime.utcnow().isoformat()

    return result


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


def write_session_record(member_id, session_id, user_message, ai_text, ai_result):
    """Write the completed chat session to DynamoDB (same schema as write-results Lambda)."""
    agent_table = dynamodb.Table(AGENT_TABLE_NAME)
    now = datetime.utcnow().isoformat()
    expires_at = int((datetime.utcnow() + timedelta(hours=24)).timestamp())

    decision_id = ai_result.get("decisionId", f"D-{int(datetime.utcnow().timestamp())}")
    agent_response = build_chat_response(ai_result)

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

    # Remove empty strings (DynamoDB doesn't allow them)
    clean_record = {k: v for k, v in session_record.items() if v != "" and v is not None}
    agent_table.put_item(Item=clean_record)

    # Write structured top-level records for dashboard/profile queries
    # AI Decision record
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
    clean_ai = {k: v for k, v in ai_decision.items() if v != "" and v is not None}
    agent_table.put_item(Item=clean_ai)

    # Individual Care Gap records
    for i, g in enumerate(ai_result.get("careGaps", [])):
        gap_id = f"GAP-{int(datetime.utcnow().timestamp())}-{i}"
        gap_record = {
            "memberId": member_id,
            "recordType": f"CARE_GAP#{gap_id}",
            "gapId": gap_id,
            "gsiRecordType": "CARE_GAP",
            "decisionId": decision_id,
            "type": g.get("type", ""),
            "priority": g.get("priority", ""),
            "protocol": g.get("protocol", ""),
            "dueWithin": g.get("dueWithin", ""),
            "status": "Open",
            "updatedAt": now,
            "expiresAt": expires_at,
        }
        clean_gap = {k: v for k, v in gap_record.items() if v != "" and v is not None}
        agent_table.put_item(Item=clean_gap)

    # Individual Intervention records
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
        clean_inv = {k: v for k, v in inv_record.items() if v != "" and v is not None}
        agent_table.put_item(Item=clean_inv)

    # Summary record with talking points
    if ai_result.get("talkingPoints"):
        summary_record = {
            "memberId": member_id,
            "recordType": f"SUMMARY#{decision_id}",
            "gsiRecordType": "SUMMARY",
            "decisionId": decision_id,
            "talkingPoints": ai_result.get("talkingPoints", []),
            "updatedAt": now,
            "expiresAt": expires_at,
        }
        agent_table.put_item(Item=summary_record)

    logger.info("Wrote SESSION#%s + AI_DECISION + %d CARE_GAPs + %d INTERVENTIONs for %s",
                session_id, 
                len(ai_result.get("careGaps", [])),
                len(ai_result.get("recommendedInterventions", [])),
                member_id)

    return {
        "decisionId": decision_id,
        "careGaps": len(ai_result.get("careGaps", [])),
        "interventions": len(ai_result.get("recommendedInterventions", []))
    }
PYTHON
    filename = "handler.py"
  }
}
