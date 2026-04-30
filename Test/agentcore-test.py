"""
AgentCore Direct Test — Tests the deployed AgentCore Runtime agent.
Calls InvokeAgentRuntime directly via boto3 to verify the agent works.

Usage:
  python Test/agentcore-test.py
  python Test/agentcore-test.py "Tell me about John Smith"
"""

import json
import sys
import uuid
import boto3

AGENT_ARN = "arn:aws:bedrock-agentcore:us-east-1:193786182229:runtime/MemberX-08pzRLFY3Q"
REGION = "us-east-1"

client = boto3.client("bedrock-agentcore", region_name=REGION)
session_id = "agentcore-test-" + uuid.uuid4().hex


def invoke(prompt):
    """Invoke AgentCore and print the response, handling all response formats."""
    print(f"\n💬 {prompt}")
    print(f"   ARN: {AGENT_ARN}")
    print(f"   Session: {session_id}")
    print(f"   Qualifier: DEFAULT\n")

    payload = json.dumps({"prompt": prompt}).encode()

    try:
        response = client.invoke_agent_runtime(
            agentRuntimeArn=AGENT_ARN,
            runtimeSessionId=session_id,
            payload=payload,
            qualifier="DEFAULT",
        )
    except Exception as e:
        print(f"❌ API Error: {e}")
        return

    content_type = response.get("contentType", "unknown")
    status = response.get("statusCode", "?")
    print(f"   Status: {status}")
    print(f"   Content-Type: {content_type}")
    print(f"   Response keys: {list(response.keys())}")

    response_body = response.get("response")
    if response_body is None:
        print("❌ No response body")
        return

    print(f"   Response type: {type(response_body).__name__}")
    print(f"\n🤖 Agent Response:\n{'─' * 60}")

    full_text = ""

    # Try as EventStream (iterable)
    try:
        for i, chunk in enumerate(response_body):
            if isinstance(chunk, bytes):
                decoded = chunk.decode("utf-8")
            elif isinstance(chunk, dict):
                decoded = json.dumps(chunk)
            else:
                decoded = str(chunk)

            # Print each chunk for debugging
            if i < 5:
                print(f"   [chunk {i}] type={type(chunk).__name__} len={len(decoded)} preview={decoded[:100]}")

            # Parse SSE lines
            for line in decoded.split("\n"):
                line = line.strip()
                if not line:
                    continue
                if line.startswith("data: "):
                    data_str = line[6:]
                    try:
                        evt = json.loads(data_str)
                        if "data" in evt:
                            print(evt["data"], end="", flush=True)
                            full_text += evt["data"]
                        elif "current_tool_use" in evt:
                            tool = evt["current_tool_use"].get("name", "")
                            if tool:
                                print(f"\n  🔧 {tool}", end="", flush=True)
                        elif "result" in evt:
                            pass
                    except json.JSONDecodeError:
                        print(data_str, end="", flush=True)
                        full_text += data_str
                else:
                    print(line, end="", flush=True)
                    full_text += line

        print(f"\n{'─' * 60}")
        print(f"   Total length: {len(full_text)} chars")
        return

    except TypeError:
        pass

    # Try as StreamingBody
    if hasattr(response_body, "read"):
        raw = response_body.read().decode("utf-8")
        print(f"   [StreamingBody] len={len(raw)}")
        try:
            result = json.loads(raw)
            text = result.get("result", raw)
            print(text)
            full_text = text
        except json.JSONDecodeError:
            print(raw)
            full_text = raw
    else:
        print(f"   Unknown response body: {response_body}")

    print(f"\n{'─' * 60}")
    print(f"   Total length: {len(full_text)} chars")


def main():
    print("\n" + "=" * 60)
    print("  🧪 AgentCore Direct Test")
    print("=" * 60)

    if len(sys.argv) > 1:
        invoke(" ".join(sys.argv[1:]))
        return

    # Interactive mode
    print(f"\n   Type a question or 'quit' to exit.\n")
    while True:
        try:
            q = input("💬 You: ").strip()
            if not q or q.lower() in ("quit", "exit", "q"):
                break
            invoke(q)
            print()
        except (KeyboardInterrupt, EOFError):
            break

    print("\nGoodbye!")


if __name__ == "__main__":
    main()
