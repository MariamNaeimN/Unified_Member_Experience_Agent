# Unified Member Experience Agent

AI-powered healthcare platform that unifies fragmented member data, delivers next-best-action recommendations, and triggers care workflows in under 30 seconds.

## What It Does

A care manager types a question about a member. The agent assembles their complete profile from 6 data sources, sends it to Amazon Bedrock (Claude 3 Haiku) for clinical analysis, identifies care gaps, triggers interventions via SNS, and returns a conversational response with talking points.

## Architecture

```
FLOW 1: DATA INGESTION            FLOW 2: AGENT CHAT
S3 -> Lambda ETL -> DynamoDB      API -> Step Functions -> Bedrock -> DynamoDB -> SNS
```

---

## Flow 1: Data Ingestion Pipeline

Raw healthcare files land in S3. Lambda ETL transforms and loads them into DynamoDB.

```
S3 Data Lake (raw/)
  members/member_enrollment.csv        (19 members)
  claims/claims_2026_q1.csv            (58 claims)
  pharmacy/pharmacy_feed_apr_2026.json (44 prescriptions)
  care-events/encounters_2026.fhir.json(42 encounters)
  conditions/conditions.json           (40 conditions)
  providers/provider_directory.csv     (37 member-provider links)
       |
       v  S3 Event Notification
  Lambda ETL Processor
    - Detects data type from prefix
    - Parses CSV/JSON
    - Transforms to single-table format
    - Batch writes to DynamoDB
    - Deletes stale records (sync)
       |
       v
  DynamoDB: unified-profile-dev
  PK: memberId    SK: recordType

  M-10042 | MEMBER#M-10042     (payer)
  M-10042 | PATIENT#M-10042    (clinical)
  M-10042 | CONDITION#CND-60001
  M-10042 | CLAIM#CLM-50001
  M-10042 | PHARMACY#RX-70001
  M-10042 | CARE_EVENT#EVT-80001
  M-10042 | PROVIDER#PRV-201   (PCP)
  M-10042 | PROVIDER#PRV-225   (Specialist)
```

One query on memberId returns the complete unified profile. Providers are member-scoped with a relationship field (PCP, Specialist, ER).

---

## Flow 2: Agent Chat Pipeline

Care manager sends a message. API Gateway routes to Lambda which starts Step Functions orchestration.

```
Sarah (Care Manager)
  "Tell me about M-10042"
       |
       v
API Gateway (Cognito JWT auth)
       |
       v
Lambda (chat-api) -> starts Step Functions -> polls for result

Step Functions: 4-Step Orchestration

  Step 1: Fetch Profile
    - Query DynamoDB (source table) for all member records
    - Query DynamoDB (agent table) for cached AI results
    - Check: source data changed? cache expired (>1h)?
    - If cached and fresh -> return cached result

  Step 2: Analyze (Bedrock Claude 3 Haiku)
    - Build prompt with full profile + chat history + care team
    - Streaming response for fast first-byte
    - Parse structured JSON: analysis, gaps, actions

  Step 3: Write Results
    - Single SESSION# record to agent output table
    - Contains: analysis, care gaps, interventions,
      notifications, talking points, chat exchange

  Step 4: Execute Workflows (SNS)
    - SMS -> patient (medication reminders)
    - TASK -> care manager (follow-up actions)
    - ALERT -> pharmacy (adherence issues)
    - REFERRAL -> specialist (appointments)
```

---

## Two DynamoDB Tables

| Table | Purpose | Records |
|-------|---------|---------|
| unified-profile-dev | Source data from S3 ETL | MEMBER, PATIENT, CONDITION, CLAIM, PHARMACY, CARE_EVENT, PROVIDER |
| agent-output-dev | Agent output per session | SESSION# records with nested analysis, gaps, interventions, notifications |

Source data stays clean. Agent output is separate with 1-hour cache TTL.

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /chat | Send message to agent (triggers full pipeline) |
| GET | /chat | Get chat history for a member |
| GET | /members | Search members by name or ID |
| GET | /members/profile | Full unified profile (both tables merged) |
| GET | /notifications | Get notifications from session records |
| PATCH | /notifications/{id} | Mark notification read/dismissed |

All endpoints require Cognito JWT token in Authorization header.

---

## Project Structure

```
IAC/
  Data_stack/          S3 + DynamoDB + Lambda ETL
    mock-data/         6 source files (260 records)
    dynamodb.tf        Source data table
    dynamodb-agent.tf  Agent output table
    lambda-etl.tf      ETL processor
    s3.tf              Data lake bucket
  Orch_stack/          Step Functions + Lambdas + SNS
    lambda-fetch.tf    Step 1: Fetch profile + cache check
    lambda-analyze.tf  Step 2: Bedrock AI analysis
    lambda-writeback.tf Step 3: Write SESSION record
    lambda-workflows.tf Step 4: SNS notifications
    stepfunctions.tf   Orchestration state machine
  API_UI/              API Gateway + Cognito + Lambda
    apigateway.tf      REST API routes + CORS
    cognito.tf         User pool + app client
    lambda-api.tf      Chat API handler
Test/
  chat-test.py         Interactive CLI chat test
project_Flow/
  README.md            Detailed architecture + walkthrough
  MOCK-DATA.md         Mock data strategy + schemas
```

---

## Deployment

Deploy in order: Data -> Orch -> API_UI.

```bash
# 1. Data Stack
cd IAC/Data_stack
terraform init && terraform apply
aws s3 sync ./mock-data/ s3://Length(terraform output -raw s3_data_lake_bucket_name)/raw/

# 2. Orch Stack
cd ../Orch_stack
terraform init && terraform apply

# 3. API_UI Stack
cd ../API_UI
terraform init
terraform apply
```

---

## Test

```bash
python Test/chat-test.py
```

```
Sarah > member M-10042
  Active member set to M-10042

Sarah > Tell me about this member
  [Agent analyzes... ~30s]
  Risk: HIGH | Care Gaps: 3 | Interventions: 4

Sarah > notifications
  [SMS] Uncontrolled diabetes - CRITICAL
  [TASK] Missed endocrinology appointments - HIGH
  [ALERT] Medication non-adherence - HIGH
  [REFERRAL] Specialist follow-up - HIGH
```

---

## AWS Services

| Service | Role |
|---------|------|
| S3 | Data lake for raw healthcare files |
| Lambda | ETL processing + API handler + orchestration steps |
| DynamoDB | Unified profiles (source) + agent output (sessions) |
| Step Functions | 4-step orchestration pipeline |
| Bedrock (Claude 3 Haiku) | AI clinical analysis with streaming |
| SNS | Downstream notifications (SMS, email, alerts) |
| API Gateway | REST API with Cognito auth |
| Cognito | User authentication (JWT) |

