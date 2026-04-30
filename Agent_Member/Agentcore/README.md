# MemberXP Agent — AgentCore Runtime Deployment

Deploys the MemberXP NLP healthcare agent to **Amazon Bedrock AgentCore Runtime** using direct Bedrock `converse_stream` API (InvokeModelWithResponseStream) with tool-use loop.

## Architecture

```
User → AgentCore Runtime → Bedrock converse_stream (Claude + tool-use) → MCP Tools REST API → Lambda → DynamoDB
```

**Key**: Uses `converse_stream` (InvokeModelWithResponseStream) directly — no Strands/LangChain abstraction. Full control over the tool-use loop with streaming response chunks.

The agent uses 12 MCP tools via the REST API to access member health data:
- `search_member` — Find members by name or ID
- `get_member_profile` — Demographics, plan, clinical data
- `get_member_analysis` — AI clinical analysis, risk assessment
- `get_member_conditions` — Active diagnoses with ICD-10 codes
- `get_member_medications` — Medications with adherence %
- `get_member_claims` — Claims history with costs
- `get_member_care_events` — Visits, ER, hospitalizations
- `get_member_care_gaps` — Open care gaps with priority
- `get_member_interventions` — Triggered workflow actions
- `get_member_notifications` — Alerts from AI analysis
- `get_all_members_summary` — All members overview
- `get_high_risk_members` — Members above risk threshold

## Prerequisites

- AWS account with credentials configured
- Python 3.10+
- Model access enabled: `anthropic.claude-3-haiku-20240307-v1:0` in Bedrock console
- MCP Tools API deployed: `https://nhudn46lcj.execute-api.us-east-1.amazonaws.com/dev`

## Setup

```bash
cd Agent_Member/Agentcore

# Create virtual environment
python -m venv .venv
.venv\Scripts\activate  # Windows
# source .venv/bin/activate  # Mac/Linux

# Install dependencies
pip install -r requirements.txt
```

## Test Locally (CLI with Streaming)

```bash
# Interactive mode with streaming output
python agent_app.py --cli

# Example conversation:
# 💬 You: Tell me about John Smith
#   🔧 search_member({"query": "John Smith"})
#   🔧 get_member_profile({"memberId": "M-10042"})
# 🤖 John Smith is a 54-year-old male...
#
# 💬 You [John Smith]: What are his conditions?
#   🔧 get_member_conditions({"memberId": "M-10042"})
# 🤖 John Smith has 2 active conditions...
```

## Test Locally (HTTP Server)

```bash
# Start the agent on port 8080
python agent_app.py

# In another terminal:
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Tell me about John Smith"}'
```

## Deploy to AgentCore Runtime

```bash
# Configure (creates .bedrock_agentcore.yaml)
agentcore configure -e agent_app.py -r us-east-1 --disable-memory

# Deploy
agentcore deploy

# Note the ARN from the output
```

## Test Deployed Agent

```bash
# Quick test
agentcore invoke '{"prompt": "Tell me about John Smith"}'

# Follow-up (memory within session)
agentcore invoke '{"prompt": "What are his conditions?"}'

# Different member
agentcore invoke '{"prompt": "Show me Maria Garcia medications"}'

# Population query
agentcore invoke '{"prompt": "Who are the high risk members?"}'
```

## Invoke Programmatically

```bash
# Set the ARN from deployment output
export AGENT_RUNTIME_ARN=arn:aws:bedrock-agentcore:us-east-1:193786182229:runtime/...

# Run interactive mode
python invoke_agent.py

# Or single question
python invoke_agent.py "Tell me about John Smith"
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_TOOLS_API_URL` | `https://nhudn46lcj.execute-api.us-east-1.amazonaws.com/dev` | MCP Tools REST API URL |
| `BEDROCK_MODEL_ID` | `anthropic.claude-3-haiku-20240307-v1:0` | Bedrock model ID |
| `AWS_REGION` | `us-east-1` | AWS region |
| `AGENT_RUNTIME_ARN` | — | AgentCore Runtime ARN (for invoke_agent.py) |

## How It Works

1. **User sends prompt** → AgentCore Runtime receives it
2. **Bedrock `converse_stream`** called with system prompt + conversation history + tool definitions
3. **Streaming response** — text chunks yielded as they arrive from Bedrock
4. **Tool-use loop** — if model requests a tool, it's executed via MCP REST API, result fed back, model continues
5. **Active member tracking** — member ID/name tracked per session for pronoun resolution ("his", "her")
6. **Up to 6 tool rounds** per question (search → profile → analysis → etc.)

## Clean Up

```bash
# Delete the AgentCore Runtime
aws bedrock-agentcore delete-agent-runtime --agent-runtime-arn <your_arn>
```
