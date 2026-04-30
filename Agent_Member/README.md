# MemberXP Agent — MCP Server

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) server that exposes the MemberXP agent-output DynamoDB tables as tools. AI assistants can query member analysis data, care gaps, interventions, and notifications through a standard stdio transport.

## Prerequisites

- Python 3.10+
- AWS credentials configured (`~/.aws/credentials`, env vars, or IAM role)
- Access to the DynamoDB tables:
  - `member-experience-agent-output-dev` (agent output)
  - `member-experience-unified-profile-dev` (source member data)

## Setup

```bash
cd Agentcore
pip install -r requirements.txt
```

## Running the server

```bash
python server.py
```

The server communicates over **stdio** (stdin/stdout), which is the standard MCP transport. It is designed to be launched by an MCP-compatible client (e.g., Kiro, Claude Desktop).

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `DYNAMODB_AGENT_TABLE_NAME` | `member-experience-agent-output-dev` | Agent output DynamoDB table |
| `DYNAMODB_SOURCE_TABLE_NAME` | `member-experience-unified-profile-dev` | Source unified-profile table |
| `AWS_REGION` | `us-east-1` | AWS region |

## Available tools

### `get_member_analysis`
Retrieve the latest AI analysis for a member.

- **Input:** `memberId` (string, required) — e.g. `"M-10042"`
- **Returns:** analysis text, risk assessment, claims insight, care history insight, medication insight, confidence score, talking points

### `get_member_care_gaps`
List care gaps identified for a member.

- **Input:** `memberId` (string, required)
- **Returns:** list of gaps with type, priority, protocol, dueWithin, status

### `get_member_interventions`
List recommended interventions for a member.

- **Input:** `memberId` (string, required)
- **Returns:** list of interventions with type, target, message, linkedGap, status

### `get_all_members_summary`
Return a summary of every member in the system.

- **Input:** none
- **Returns:** list of members with memberId, firstName, lastName, planName, riskScore

### `get_member_notifications`
Retrieve notifications from AI analysis sessions.

- **Input:** `memberId` (string, optional) — omit to get all notifications
- **Returns:** list of notifications with type, title, message, priority, status

### `get_high_risk_members`
Return members whose risk score meets or exceeds a threshold.

- **Input:** `min_risk_score` (integer, optional, default `80`)
- **Returns:** filtered list of high-risk members sorted by risk score descending

## MCP client configuration

Add this to your MCP client config (e.g., `.kiro/settings/mcp.json`):

```json
{
  "mcpServers": {
    "memberxp-agent": {
      "command": "python",
      "args": ["Agentcore/server.py"],
      "env": {
        "AWS_REGION": "us-east-1"
      }
    }
  }
}
```

## Data model

Both DynamoDB tables use a single-table design:

- **Partition key:** `memberId` (e.g. `"M-10042"`)
- **Sort key:** `recordType` (e.g. `"AI_DECISION#D-123"`, `"CARE_GAP#GAP-456"`)
- **GSI:** `recordType-index` — partition key `gsiRecordType`, sort key `memberId`

### Record types in the agent-output table

| Prefix | Description |
|---|---|
| `AI_DECISION#` | Full AI analysis with risk, insights, confidence |
| `CARE_GAP#` | Individual care gap (screening, lab, follow-up) |
| `INTERVENTION#` | Recommended action (alert, outreach, referral) |
| `SESSION#` | Chat session with embedded notifications |
| `SUMMARY#` | Condensed talking points and agent response |
