"""Test AgentCore memory — sends multiple questions in the same session."""
import json, uuid, boto3, time

AGENT_ARN = "arn:aws:bedrock-agentcore:us-east-1:193786182229:runtime/MemberX-08pzRLFY3Q"
client = boto3.client("bedrock-agentcore")
SESSION_ID = "memory-test-" + uuid.uuid4().hex

QUESTIONS = [
    "Tell me about John Smith",
    "What are his medications?",
    "Show me Maria Garcia conditions",
    "And her claims?",
]

def invoke(prompt):
    payload = json.dumps({"prompt": prompt}).encode()
    start = time.time()
    response = client.invoke_agent_runtime(
        agentRuntimeArn=AGENT_ARN,
        runtimeSessionId=SESSION_ID,
        payload=payload,
        qualifier="DEFAULT",
    )
    body = response.get("response")
    full_text = ""
    buf = ""
    while True:
        raw = body.read(512)
        if not raw:
            break
        buf += raw.decode("utf-8")
        while "\n" in buf:
            line, buf = buf.split("\n", 1)
            line = line.strip()
            if not line or not line.startswith("data: "):
                continue
            data_str = line[6:].strip()
            try:
                inner = json.loads(data_str)
            except:
                full_text += data_str
                continue
            if isinstance(inner, str):
                for part in inner.strip().split("\n"):
                    part = part.strip()
                    if not part:
                        continue
                    try:
                        evt = json.loads(part)
                        if evt.get("type") == "chunk":
                            full_text += evt.get("content", "")
                        elif evt.get("type") == "tool_use":
                            full_text += f"\n[TOOL: {evt.get('tool', '')}]\n"
                    except:
                        full_text += part
            elif isinstance(inner, dict):
                if inner.get("type") == "chunk":
                    full_text += inner.get("content", "")
                elif inner.get("type") == "tool_use":
                    full_text += f"\n[TOOL: {inner.get('tool', '')}]\n"
    elapsed = time.time() - start
    return full_text.strip(), elapsed

print(f"\nSession: {SESSION_ID}\n")
for q in QUESTIONS:
    print(f"💬 {q}")
    answer, elapsed = invoke(q)
    preview = answer[:200] + "..." if len(answer) > 200 else answer
    print(f"🤖 ({elapsed:.1f}s) {preview}\n")
print("Done!")
