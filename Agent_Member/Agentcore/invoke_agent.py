"""
Invoke the MemberXP Agent on AgentCore Runtime — Interactive with Memory.

The same session ID is reused across all turns so the agent remembers
which member you're talking about.

Usage:
  python invoke_agent.py                          # interactive mode
  python invoke_agent.py "Tell me about John"     # single question

Examples:
  💬 Tell me about John Smith
  💬 What are his medications?       ← agent remembers John
  💬 Show me Maria Garcia conditions ← switches to Maria
  💬 And her claims?                 ← agent remembers Maria
"""

import json
import sys
import uuid
import os

import boto3

AGENT_ARN = os.environ.get(
    "AGENT_RUNTIME_ARN",
    "arn:aws:bedrock-agentcore:us-east-1:193786182229:runtime/MemberX-08pzRLFY3Q"
)

client = boto3.client("bedrock-agentcore")

# Single session ID for the entire conversation — AgentCore keeps state per session
SESSION_ID = "interactive-" + uuid.uuid4().hex


def invoke(prompt):
    """Invoke AgentCore and stream the response. Reuses SESSION_ID for memory."""
    payload = json.dumps({"prompt": prompt}).encode()

    response = client.invoke_agent_runtime(
        agentRuntimeArn=AGENT_ARN,
        runtimeSessionId=SESSION_ID,
        payload=payload,
        qualifier="DEFAULT",
    )

    full_text = ""
    body = response.get("response")
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
            except json.JSONDecodeError:
                print(data_str, end="", flush=True)
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
                            t = evt.get("content", "")
                            print(t, end="", flush=True)
                            full_text += t
                        elif evt.get("type") == "tool_use":
                            print(f"\n  🔧 {evt.get('tool', '')}", end="", flush=True)
                    except json.JSONDecodeError:
                        print(part, end="", flush=True)
                        full_text += part
            elif isinstance(inner, dict):
                if inner.get("type") == "chunk":
                    t = inner.get("content", "")
                    print(t, end="", flush=True)
                    full_text += t
                elif inner.get("type") == "tool_use":
                    print(f"\n  🔧 {inner.get('tool', '')}", end="", flush=True)

    if buf.strip():
        print(buf.strip(), end="", flush=True)

    print()
    return full_text


def main():
    print(f"\n🏥 MemberXP Agent (AgentCore)")
    print(f"   Session: {SESSION_ID}")
    print(f"   Memory persists across turns — ask follow-ups!\n")

    # Single question mode
    if len(sys.argv) > 1:
        prompt = " ".join(sys.argv[1:])
        print(f"💬 {prompt}\n")
        print("🤖 ", end="", flush=True)
        invoke(prompt)
        return

    # Interactive mode
    print("   Examples:")
    print("     💬 Tell me about John Smith")
    print("     💬 What are his medications?")
    print("     💬 Show me Maria Garcia conditions")
    print("     💬 And her claims?")
    print("   Type 'quit' to exit.\n")

    while True:
        try:
            q = input("💬 You: ").strip()
            if not q or q.lower() in ("quit", "exit", "q"):
                break
            print("\n🤖 ", end="", flush=True)
            invoke(q)
            print()
        except (KeyboardInterrupt, EOFError):
            break

    print("\nGoodbye!")


if __name__ == "__main__":
    main()
