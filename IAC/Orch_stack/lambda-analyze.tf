# =============================================================================
# Lambda: Analyze Profile - Step 2 of orchestration
# Sends unified profile to Bedrock LLM for AI analysis
# Covers: Analyze claims/care/history, Determine next-best action, Trigger workflows
# =============================================================================

resource "aws_cloudwatch_log_group" "analyze_profile" {
  name              = "/aws/lambda/${var.project_name}-analyze-profile-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "analyze_profile" {
  function_name = "${var.project_name}-analyze-profile-${var.environment}"
  description   = "Step 2: Send profile to Bedrock for AI analysis and recommendations"
  role          = aws_iam_role.lambda_orch_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  filename         = data.archive_file.analyze_profile.output_path
  source_code_hash = data.archive_file.analyze_profile.output_base64sha256

  environment {
    variables = {
      BEDROCK_MODEL_ID = var.bedrock_model_id
      ENVIRONMENT      = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-analyze-profile"
    Role = "Step 2 - Bedrock AI Analysis"
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.analyze_profile]
}

data "archive_file" "analyze_profile" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-analyze-profile.zip"

  source {
    content  = <<-PYTHON
import json
import os
import logging
import boto3
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock = boto3.client("bedrock-runtime")
MODEL_ID = os.environ["BEDROCK_MODEL_ID"]


def lambda_handler(event, context):
    member_id = event.get("memberId")
    profile = event.get("profile")
    chat_history = event.get("chatHistory", [])
    user_message = event.get("userMessage", "Analyze this member")
    session_id = event.get("sessionId", "")

    if not profile or not profile.get("member"):
        return {
            "memberId": member_id,
            "profile": profile,
            "aiResult": None,
            "error": "No profile data to analyze"
        }

    logger.info("Analyzing profile for %s (session: %s)", member_id, session_id)

    prompt = build_prompt(profile, chat_history, user_message)

    # Build messages with chat history for conversation context
    messages = []
    for ch in chat_history[-5:]:
        messages.append({"role": "user", "content": ch.get("userMessage", "")})
        messages.append({"role": "assistant", "content": ch.get("agentResponse", "")})
    messages.append({"role": "user", "content": prompt})

    # Use streaming API for faster time-to-first-byte
    response = bedrock.invoke_model_with_response_stream(
        modelId=MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "temperature": 0.2,
            "messages": messages
        })
    )

    # Collect streamed chunks into full response
    ai_text = ""
    chunk_count = 0
    for event in response["body"]:
        chunk = json.loads(event["chunk"]["bytes"])
        if chunk.get("type") == "content_block_delta":
            delta = chunk.get("delta", {})
            if delta.get("type") == "text_delta":
                ai_text += delta.get("text", "")
                chunk_count += 1

    logger.info("Bedrock streaming complete: %d chunks, %d chars", chunk_count, len(ai_text))

    ai_result = parse_ai_response(ai_text, member_id)

    return {
        "memberId": member_id,
        "profile": profile,
        "aiResult": ai_result
    }


def build_prompt(profile, chat_history=None, user_message=""):
    member = profile.get("member", {})
    patient = profile.get("patient", {})
    conditions = profile.get("conditions", [])
    claims = profile.get("claims", [])
    pharmacy = profile.get("pharmacy", [])
    events = profile.get("careEvents", [])

    parts = []
    parts.append("You are a healthcare AI clinical decision support chatbot. A care manager is asking you about a member.")
    parts.append("Respond conversationally but include structured clinical analysis.")
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
    # Pre-calculate age — don't show DOB to prevent LLM from recalculating incorrectly
    dob = member.get("dob", "")
    age_str = ""
    if dob:
        try:
            from datetime import datetime as dt
            born = dt.strptime(dob, "%Y-%m-%d")
            today = dt.utcnow()
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
            # Pre-flag for the LLM so it doesn't miscalculate
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
        parts.append("IMPORTANT: Only flag medications as non-adherent if they are explicitly marked FLAGGED above. Do NOT flag medications marked OK.")
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

    parts.append("INSTRUCTIONS:")
    parts.append("1. Provide a clinical analysis covering claims patterns, care engagement, and medication adherence")
    parts.append("2. Identify ALL care gaps with priority and clinical protocol")
    parts.append("3. For EACH care gap, specify a concrete workflow action to trigger:")
    parts.append("   - SMS: text message to the patient (include exact message text)")
    parts.append("   - TASK: task for care team member (include who and what)")
    parts.append("   - ALERT: alert to pharmacy or specialist (include who and what)")
    parts.append("   - REFERRAL: referral to specialist or program (include details)")
    parts.append("4. Provide 5 talking points for the care manager next call")
    parts.append("5. Consider allergies when recommending medication-related actions")
    parts.append("6. Consider living situation for social determinant risks")
    parts.append("")
    parts.append('RESPOND IN THIS EXACT JSON FORMAT:')
    parts.append('{')
    parts.append('  "analysis": "2-3 sentence clinical summary",')
    parts.append('  "riskAssessment": "HIGH/MEDIUM/LOW with explanation",')
    parts.append('  "claimsInsight": "1-2 sentences on claims patterns",')
    parts.append('  "careHistoryInsight": "1-2 sentences on care engagement",')
    parts.append('  "medicationInsight": "1-2 sentences on medication adherence",')
    parts.append('  "careGaps": [')
    parts.append('    {"type": "gap description", "priority": "CRITICAL/HIGH/MEDIUM/LOW", "protocol": "protocol name", "dueWithin": "timeframe"}')
    parts.append('  ],')
    parts.append('  "recommendedInterventions": [')
    parts.append('    {"type": "SMS/TASK/ALERT/REFERRAL", "target": "patient/care_manager/pharmacy/specialist", "message": "action text", "linkedGap": "gap reference", "system": "SNS/CareManagement/PharmacySystem/ReferralSystem"}')
    parts.append('  ],')
    parts.append('  "talkingPoints": ["point 1", "point 2", "point 3", "point 4", "point 5"],')
    parts.append('  "confidence": 0.0')
    parts.append('}')
    parts.append("")
    parts.append("Respond ONLY with valid JSON. No markdown, no explanation outside the JSON.")

    return "\n".join(parts)


def parse_ai_response(ai_text, member_id):
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
PYTHON
    filename = "handler.py"
  }
}
