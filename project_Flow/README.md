# Unified Member Experience Orchestration Agent

## Executive Summary

A serverless, AI-powered platform that unifies fragmented healthcare member data in real time, delivers intelligent next-best-action recommendations, and automatically triggers care workflows — all within seconds.

---

## Business Outcome

This agent directly impacts the metrics that matter most to healthcare organizations:

| Outcome | Impact |
|---------|--------|
| Reduce care manager prep time | From 20-30 minutes to under 30 seconds per member |
| Increase care gap closure rate | AI catches gaps humans miss — medication lapses, missed referrals, overdue screenings |
| Lower avoidable readmissions | Proactive interventions triggered before patients deteriorate |
| Improve member satisfaction (NPS) | Faster, more informed interactions with care teams |
| Reduce operational cost per member | Fewer manual touches, automated workflows replace repetitive coordination |
| Accelerate time to intervention | From days/weeks to seconds — real-time next-best-action at point of contact |

The bottom line: this agent turns every care manager interaction from reactive and fragmented into proactive, AI-assisted, and fully documented.

---

## Problem Statement

Healthcare payers and care management organizations struggle with **fragmented member data** spread across multiple disconnected systems (claims, care management, pharmacy, EHR). This leads to:

- Care managers spending 20-30 minutes manually piecing together a member's picture
- Missed care gaps and medication non-adherence going undetected
- Delayed interventions resulting in avoidable ER visits and hospitalizations
- No unified audit trail of decisions and actions taken

---

## Solution

An AI-driven chat agent that care managers interact with conversationally:

1. **Builds a unified member profile** in real time from multiple data sources
2. **Analyzes claims, care history, and risk factors** using Amazon Bedrock (Claude 3 Haiku) with streaming responses
3. **Determines the next-best action** with ranked recommendations
4. **Triggers automated workflows** across downstream systems via Amazon SNS (SMS, email, alerts)
5. **Streams conversational responses** to care managers with talking points and clinical insights
6. **Maintains chat history** so care managers can have follow-up conversations with full context

---

## Target Customers

| Segment | Examples |
|---------|---------|
| Healthcare Payers | Optum, UnitedHealth Group, Aetna, Humana |
| Care Management Organizations | Evolent Health, Amedisys |
| Health Systems | Large hospital networks, ACOs |

---

## Data Model / Ontology

A complete view of the core entities, covering both the payer side (insurance/plan) and the clinical side (patient health), plus operational entities for AI decisions and workflows.

### Entity Relationship Diagram

```
                         ┌──────────────────┐
                         │     MEMBER        │
                         │  (Payer Side)     │
                         │──────────────────│
                         │ memberId (PK)     │
                         │ name              │
                         │ dob               │
                         │ plan              │
                         │ coverageStatus    │
                         │ enrollmentDate    │
                         └────────┬─────────┘
                                  │ 1:1
                                  ▼
                         ┌──────────────────┐
                         │     PATIENT       │
                         │  (Clinical Side)  │
                         │──────────────────│
                         │ patientId (PK)    │
                         │ memberId (FK)     │
                         │ riskScore         │
                         │ pcpId (FK)        │
                         │ allergies[]       │
                         │ bloodType         │
                         │ livingSituation   │
                         └────────┬─────────┘
                                  │
          ┌───────────┬───────────┼───────────┬──────────────┐
          ▼           ▼           ▼           ▼              ▼
 ┌──────────────┐ ┌────────────┐ ┌─────────────┐ ┌────────────┐ ┌──────────────┐
 │  CONDITION    │ │  CLAIM      │ │  PHARMACY    │ │ CARE EVENT  │ │  PROVIDER     │
 │──────────────│ │────────────│ │─────────────│ │────────────│ │──────────────│
 │ conditionId  │ │ claimId    │ │ rxId         │ │ eventId    │ │ providerId   │
 │ patientId(FK)│ │ memberId(FK)│ │ patientId(FK)│ │ patientId(FK)│ │ name        │
 │ diagnosis    │ │ type       │ │ medication   │ │ eventType  │ │ specialty    │
 │ icdCode      │ │ diagnosis  │ │ dosage       │ │ providerId │ │ facility     │
 │ onsetDate    │ │ providerId │ │ prescriber   │ │ date       │ │ npi          │
 │ status       │ │ date       │ │ lastRefill   │ │ diagnosis  │ │ phone        │
 │ (active/     │ │ amount     │ │ daysSupply   │ │ outcome    │ │ inNetwork    │
 │  resolved)   │ │ status     │ │ adherence%   │ │ notes      │ └──────────────┘
 └──────────────┘ └────────────┘ │ status       │ └────────────┘
                                  └─────────────┘
          │
          ▼
 ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
 │   CARE GAP        │    │   AI DECISION     │    │   CARE PLAN       │
 │──────────────────│    │──────────────────│    │──────────────────│
 │ gapId (PK)        │    │ decisionId (PK)   │    │ planId (PK)       │
 │ patientId (FK)    │    │ patientId (FK)    │    │ patientId (FK)    │
 │ type              │    │ analysis          │    │ programName       │
 │ protocol          │    │ actions[]         │    │ enrollmentDate    │
 │ dueDate           │    │ confidence        │    │ status            │
 │ priority          │    │ model             │    │ goals[]           │
 │ status (open/     │    │ timestamp         │    │ assignedTeam      │
 │  in_progress/     │    └──────────────────┘    └──────────────────┘
 │  closed)          │
 │ closedDate        │
 └──────────────────┘
          │
          ▼
 ┌──────────────────┐    ┌──────────────────┐
 │   INTERVENTION    │    │  MEMBER SUMMARY   │
 │──────────────────│    │──────────────────│
 │ interventionId   │    │ summaryId (PK)    │
 │ patientId (FK)   │    │ patientId (FK)    │
 │ gapId (FK)       │    │ generatedBy       │
 │ decisionId (FK)  │    │ summaryText       │
 │ type (SMS/task/  │    │ talkingPoints[]   │
 │  alert/referral) │    │ riskAssessment    │
 │ status           │    │ timestamp         │
 │ triggeredAt      │    │ expiresAt         │
 │ completedAt      │    └──────────────────┘
 │ outcome          │
 └──────────────────┘
                         ┌──────────────────┐
                         │  CHAT HISTORY     │
                         │──────────────────│
                         │ chatId (PK)       │
                         │ memberId (FK)     │
                         │ sessionId         │
                         │ userMessage       │
                         │ agentResponse     │
                         │ decisionId (FK)   │
                         │ timestamp         │
                         └──────────────────┘
```

### Entity Reference

| Entity | Side | Stored In | Purpose |
|--------|------|-----------|---------|
| Member | Payer | DynamoDB | Insurance profile — plan, coverage, enrollment |
| Patient | Clinical | DynamoDB | Clinical profile — risk score, PCP, allergies, living situation |
| Condition | Clinical | S3 (raw) → DynamoDB | Chronic conditions and active diagnoses (diabetes, COPD, etc.) |
| Claim | Payer | S3 (raw) → DynamoDB | Claims history — ER visits, procedures, costs |
| Pharmacy | Clinical | S3 (raw) → DynamoDB | Medications, refill history, adherence tracking |
| Care Event | Clinical | S3 (raw) → DynamoDB | Visits, discharges, lab results, missed appointments |
| Provider | Reference | DynamoDB | Doctors, specialists, facilities — linked to events and plans |
| Care Gap | Operational | DynamoDB | AI-identified gaps with lifecycle (open → in_progress → closed) |
| Care Plan | Clinical | DynamoDB | Program enrollment, goals, assigned care team |
| AI Decision | Operational | DynamoDB | Full audit trail of every AI recommendation and confidence score |
| Intervention | Operational | DynamoDB | Triggered actions (SMS, tasks, alerts) linked to gaps and decisions |
| Member Summary | Operational | DynamoDB | AI-generated summaries and talking points for care managers |
| Chat History | Operational | DynamoDB | Conversation log — Sarah's questions + agent responses, linked to member and session |

### How It Maps to the John Smith Example

| What the System Shows | Entity Source |
|-----------------------|---------------|
| John Smith, Gold PPO plan | Member (plan) + Patient (demographics) |
| 3 ER visits for diabetes | Care Event (eventType: ER) + Claim (diagnosis) |
| Diabetes as chronic condition | Condition (diagnosis: Type 2 Diabetes, status: active) |
| Insulin not refilled 45 days | Pharmacy (lastRefill, adherence%) |
| 2 missed endocrinologist appts | Care Event (eventType: missed_appointment) |
| "High risk" flag | Patient (riskScore) — derived from Conditions + Claims + Pharmacy |
| Dr. Patel (endocrinologist) | Provider (specialty: endocrinology) |
| AI says "care disengagement" | AI Decision (analysis, confidence, actions[]) |
| SMS sent, task created | Intervention (type: SMS, status: delivered) |
| "Diabetes management program" | Care Plan (programName, status: ready_to_enroll) |
| Talking points for Sarah | Member Summary (talkingPoints[], riskAssessment) |
| Sarah's conversation with agent | Chat History (userMessage, agentResponse, sessionId) |

---

## AWS Architecture

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                   CARE MANAGER (Sarah) — Chat Interface          │
└──────────────────────────┬───────────────────────────────────────┘
                           │ "Tell me about M-10042"
                           ▼
                  ┌─────────────────┐
                  │   CloudFront     │ ◄── Static Chat UI from S3
                  │   (CDN / UI)     │
                  └────────┬────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │  API Gateway     │ ◄── REST API + Auth (IAM/Cognito)
                  │  (Secure Entry)  │
                  └────────┬────────┘
                           │
                           ▼
          ┌────────────────────────────────────────────────────────┐
          │         AWS Step Functions                              │
          │         (Orchestration Engine — 4 Steps)                │
          │                                                        │
          │  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌───────┐│
          │  │  STEP 1   │  │  STEP 2   │  │  STEP 3  │  │STEP 4 ││
          │  │  Fetch    │─►│  Bedrock  │─►│  Write   │─►│Trigger││
          │  │  Profile  │  │  Analyze  │  │  Results │  │Notify ││
          │  │  + Chat   │  │  Stream   │  │  + Chat  │  │(SNS)  ││
          │  │  History  │  │           │  │  History │  │       ││
          │  └──────────┘  └───────────┘  └──────────┘  └───────┘│
          └────────────────────────────────────────────────────────┘
              │                │               │             │
              ▼                ▼               ▼             ▼
      ┌────────────┐   ┌───────────┐   ┌──────────┐  ┌──────────┐
      │ DynamoDB    │   │  Amazon   │   │ DynamoDB  │  │ Amazon   │
      │ (Read       │   │  Bedrock  │   │ (Write    │  │ SNS      │
      │  Profile +  │   │  Claude   │   │  AI Decn, │  │ (SMS,    │
      │  Chat Hist) │   │  Streaming│   │  Gaps,    │  │  Email,  │
      │             │   │           │   │  Chat Hist│  │  Alerts) │
      └────────────┘   └───────────┘   └──────────┘  └──────────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │  S3 Data Lake     │
                                    │  (Raw: claims,    │
                                    │   pharmacy, care, │
                                    │   conditions)     │
                                    └──────────────────┘
```


### AWS Services & Responsibilities

| AWS Service | Role | Why This Service |
|-------------|------|------------------|
| **Amazon S3** | Stores raw healthcare datasets (claims, care, pharmacy, history) + static chat UI assets | Scalable data lake, decoupled from source systems |
| **Amazon CloudFront** | CDN for low-latency chat UI delivery | Fast global access for care managers |
| **Amazon API Gateway** | Secure REST API entry point with rate limiting and auth | Managed API layer, no servers to maintain |
| **AWS Lambda** | Compute for profile fetch, AI analysis, result write-back, workflow execution (4 functions) | Serverless, pay-per-use, scales automatically |
| **Amazon Bedrock (Claude 3 Haiku)** | AI reasoning via streaming — context analysis, risk scoring, next-best-action, conversational responses | Managed LLM, no model infrastructure, data stays in AWS boundary |
| **AWS Step Functions** | Orchestrates the 4-step pipeline (fetch → analyze → write → notify) with smart caching | Visual workflows, built-in retries, full audit trail |
| **Amazon DynamoDB** | Single-table design for unified profiles, AI decisions, chat history, and audit logs | Single-digit ms latency, serverless, scales to any volume |
| **Amazon SNS** | Downstream workflow triggers — SMS to patients, email alerts to care team, pharmacy notifications | Serverless pub/sub, multi-channel delivery |
| **AWS IAM** | Fine-grained access control across all services | Least-privilege security, compliance-ready |

---

## End-to-End Flow

### Step-by-Step Walkthrough

```
 SARAH (Chat)                   SYSTEM RESPONSE
 ────────────                   ───────────────

 1. Sarah types:                API Gateway routes to Step Functions
    "Tell me about M-10042"     with memberId, userMessage, sessionId
         │
         ▼
 2. Step 1: Fetch Profile       Lambda queries DynamoDB by memberId
    + check staleness            Gets all records (member, patient,
         │                       conditions, claims, pharmacy, events)
         │                      Loads previous chat history (last 10)
         │                      Checks: source data changed since
         │                       last AI analysis?
         │
    ┌────┴────┐
    NO        YES
    │         │
    ▼         ▼
 Return     Continue
 cached     to Step 2
    │         │
    │         ▼
    │  3. Step 2: Analyze        Lambda sends profile + chat history
    │     (Bedrock Streaming)     to Bedrock Claude 3 Haiku
    │         │                  Bedrock streams response chunk by
    │         │                   chunk (faster time-to-first-byte)
    │         │                  Analyzes: claims patterns, care
    │         │                   history, medication adherence
    │         │                  Determines: care gaps, next-best
    │         │                   actions, talking points
    │         ▼
    │  4. Step 3: Write Results  Lambda writes to DynamoDB:
    │         │                  • AI_DECISION# (analysis, risk)
    │         │                  • CARE_GAP# (one per gap)
    │         │                  • INTERVENTION# (SMS, tasks, alerts)
    │         │                  • SUMMARY# (talking points, 24hr TTL)
    │         │                  • CHAT_HISTORY# (Sarah's question +
    │         │                     agent's conversational response)
    │         ▼
    │  5. Step 4: Execute        Lambda routes each intervention
    │     Workflows (SNS)         to downstream systems:
    │         │                  • SMS → SNS → patient phone
    │         │                  • TASK → SNS → care manager email
    │         │                  • ALERT → SNS → pharmacy team
    │         │                  • REFERRAL → SNS → specialist
    │         │                  Updates DynamoDB: "Triggered" → "Delivered"
    │         │
    └────┬────┘
         │
         ▼
 6. Sarah sees streaming        Agent response appears in chat:
    response in chat UI          analysis, gaps, actions, talking points
                                 Chat history persists for follow-ups
```

### Smart Caching

| Scenario | What Happens | Bedrock Called? |
|----------|-------------|----------------|
| First time for this member | No AI results exist → full analysis | Yes |
| Same data, asked again | Source unchanged → return cached response | No (saves cost + time) |
| Profile updated (new claim, pharmacy change) | Source changed → re-run full analysis | Yes |
| Sarah says "forceReanalyze: true" | Always re-run regardless | Yes |

### Chat History & Conversation Context

When Sarah asks a follow-up question about the same member, Bedrock receives the last 5 conversation exchanges as context. This enables natural follow-ups:

```
Sarah: "Tell me about M-10042"
Agent: "John Smith is a 58-year-old with uncontrolled diabetes..."

Sarah: "What about his medication adherence?"
Agent: "As I mentioned, John's insulin is 15 days overdue and his
        metformin adherence is at 62%. Here's what I recommend..."

Sarah: "Schedule the endocrinologist appointment"
Agent: "I've triggered a scheduling task for Dr. Rivera within 14 days.
        The care team has been notified..."
```

Each exchange is stored as a `CHAT_HISTORY#` record in DynamoDB, linked to the member and session.

---

## Real-World Example

**Scenario:** Sarah, a care manager at a large health plan, is about to call member John Smith (M-10042). Today, she opens the Unified Member Experience portal instead of logging into 4 separate systems.

### Step 1 — Sarah Searches for John

Sarah types "John Smith" into the portal. Behind the scenes, the system assembles his complete picture from raw data that was already ingested and processed:

```
 Raw Data (S3 Data Lake)                    Processed Data (DynamoDB)
 ───────────────────────                    ────────────────────────
 claims_2026_q1.csv      ──► Lambda ETL ──► Claim records for M-10042
 pharmacy_feed_apr.json  ──► Lambda ETL ──► Pharmacy records (insulin, metformin)
 ehr_encounters.fhir     ──► Lambda ETL ──► Care Events (ER visits, missed appts)
 provider_directory.csv  ──► Lambda ETL ──► Provider links (Dr. Patel, Dr. Rivera)
```

Lambda reads the processed records from DynamoDB in milliseconds and assembles the unified profile.

### Step 2 — The Unified Profile

| Entity | What the System Finds | Data Source |
|--------|----------------------|-------------|
| **Member** | Gold PPO plan, enrolled since 2019, active coverage | Member table (DynamoDB) |
| **Patient** | Age 58, lives alone, risk score: HIGH (92/100) | Patient table (DynamoDB) |
| **Conditions** | Type 2 Diabetes (active since 2021), Hypertension (active since 2018) | Condition table (DynamoDB) |
| **Claims** | 3 ER visits in 6 months — all diabetes-related (ICD-10: E11.65) | Claim table (DynamoDB, raw in S3) |
| **Pharmacy** | Insulin Glargine: last refill 45 days ago (30-day supply → 15 days overdue). Metformin: adherence 62% (below 80% threshold) | Pharmacy table (DynamoDB, raw in S3) |
| **Care Events** | 2 missed endocrinologist appointments (Dr. Rivera). Last PCP visit: 4 months ago (Dr. Patel) | Care Event table (DynamoDB, raw in S3) |
| **Providers** | PCP: Dr. Patel (in-network). Endocrinologist: Dr. Rivera (in-network). Nearest pharmacy: CVS on Main St. | Provider table (DynamoDB) |
| **Care Plan** | Diabetes Management Program — status: eligible, not enrolled | Care Plan table (DynamoDB) |

### Step 3 — Bedrock Agent Analyzes

Step Functions sends the assembled profile to the Bedrock Agent. The LLM reasons across all entities:

> **AI Analysis (stored as AI Decision):**
> "John Smith is a 58-year-old male with uncontrolled Type 2 Diabetes and Hypertension. He lives alone with no caregiver support. Key risk indicators: (1) 3 ER visits in 6 months for diabetes complications, (2) insulin non-adherence — 15 days overdue on refill, (3) metformin adherence at 62%, well below the 80% clinical threshold, (4) 2 missed specialist appointments suggesting care disengagement, (5) no PCP visit in 4 months. Combined risk score: 92/100. Estimated 30-day hospitalization probability: HIGH."

> **Care Gaps Identified (stored as Care Gap records):**

| Priority | Gap | Protocol | Due |
|----------|-----|----------|-----|
| 🔴 Critical | Insulin refill overdue (15 days) | Diabetes med adherence protocol | Immediate |
| 🔴 Critical | Metformin adherence below threshold (62%) | Medication therapy management | Within 7 days |
| 🟡 High | No endocrinologist visit in 6+ months | Specialist follow-up protocol | Within 14 days |
| 🟡 High | No PCP visit in 4 months | Annual wellness / chronic care | Within 30 days |
| 🟢 Medium | Not enrolled in Diabetes Management Program | Care program enrollment | Within 30 days |

### Step 4 — Workflows Trigger Automatically

Based on the AI decision, Step Functions fires interventions (each stored as an Intervention record linked to the Care Gap and AI Decision):

```
AI Decision (decisionId: D-88421)
      │
      ├──► Intervention: SMS to John
      │    "Hi John, it looks like your insulin refill is overdue.
      │     We can help — reply YES to connect with your pharmacy."
      │    → Status: Delivered ✅
      │    → Linked to: Care Gap (insulin refill overdue)
      │
      ├──► Intervention: Alert pharmacy team (CVS Main St.)
      │    "Patient M-10042: Insulin Glargine refill overdue 15 days.
      │     Metformin adherence 62%. Pharmacist review requested."
      │    → Status: Sent ✅
      │    → Linked to: Care Gap (metformin adherence)
      │
      ├──► Intervention: Schedule endocrinologist
      │    Auto-book with Dr. Rivera within 14 days
      │    → Status: Pending confirmation
      │    → Linked to: Care Gap (specialist follow-up)
      │
      ├──► Intervention: Create PCP follow-up task
      │    "Schedule wellness visit with Dr. Patel for M-10042"
      │    → Status: Task created
      │    → Linked to: Care Gap (PCP visit overdue)
      │
      └──► Intervention: Flag for program enrollment
           "M-10042 eligible for Diabetes Management Program.
            Care manager to discuss during next call."
           → Status: Ready for discussion
           → Linked to: Care Gap (program enrollment)
```

### Step 5 — What Sarah Actually Sees

Instead of 20-30 minutes across 4 systems, Sarah sees one screen in under 30 seconds:

```
┌──────────────────────────────────────────────────────────────────┐
│  🟡 JOHN SMITH (M-10042) — RISK: HIGH (92/100)                  │
│  Age: 58 | Plan: Gold PPO | PCP: Dr. Patel | Lives alone        │
│                                                                  │
│  Active Conditions:                                              │
│  • Type 2 Diabetes (since 2021) — UNCONTROLLED                  │
│  • Hypertension (since 2018) — managed                          │
│                                                                  │
│  ⚠️  Medications at Risk:                                        │
│  • Insulin Glargine — 15 days overdue (SMS sent to patient)     │
│  • Metformin — 62% adherence (pharmacist alerted)               │
│                                                                  │
│  AI Summary:                                                     │
│  "John is disengaged from care. Diabetes is uncontrolled with   │
│   frequent ER use and medication non-adherence. High risk for   │
│   hospitalization within 30 days. Immediate focus: medication   │
│   gap and specialist re-engagement."                            │
│                                                                  │
│  Care Gaps:                              Status:                 │
│  🔴 Insulin refill overdue               SMS sent to patient    │
│  🔴 Metformin adherence low              Pharmacist alerted     │
│  🟡 Endocrinologist overdue             Appt being scheduled    │
│  🟡 PCP visit overdue                   Task created            │
│  🟢 Diabetes program enrollment         Ready to discuss        │
│                                                                  │
│  📋 Talking Points for This Call:                                │
│  1. Ask John about insulin — why hasn't he refilled?            │
│  2. Discuss metformin — is he experiencing side effects?        │
│  3. Offer to reschedule with Dr. Rivera (endocrinologist)       │
│  4. Mention Diabetes Management Program — benefits & support    │
│  5. Ask about living situation — does he need home support?     │
│                                                                  │
│  Recent Actions:                         Triggered:              │
│  ✅ SMS sent to patient                   2 min ago              │
│  ✅ Pharmacy team alerted                 2 min ago              │
│  🔄 Endo appointment                     Scheduling...          │
│  🔄 PCP task created                     Awaiting assignment    │
└──────────────────────────────────────────────────────────────────┘
```

### Step 6 — Everything Is Logged

Every piece of this interaction is stored for compliance and continuity:

| What | Where | Why |
|------|-------|-----|
| Raw claims, pharmacy, EHR files | S3 (Data Lake) | Source of truth, compliance archive |
| Unified profile | DynamoDB (Patient + Member) | Fast retrieval for next interaction |
| AI analysis & confidence score | DynamoDB (AI Decision) | Audit trail — what the AI said and why |
| Care gaps identified | DynamoDB (Care Gap) | Track lifecycle: open → in_progress → closed |
| Every intervention fired | DynamoDB (Intervention) | What was triggered, when, and outcome |
| Summary & talking points | DynamoDB (Member Summary) | Reusable until next profile refresh |
| Chat conversation | DynamoDB (Chat History) | Full conversation log — Sarah's questions + agent responses |

### The Business Outcome

| Without This System | With This System |
|---------------------|------------------|
| Sarah logs into 4 systems, takes 25 minutes | One screen, 30 seconds |
| She might miss the insulin gap | AI catches it instantly, SMS already sent |
| No talking points — she wings the call | 5 tailored talking points ready |
| Follow-ups require manual coordination | 5 interventions already triggered |
| No record of what was decided or why | Full audit trail: AI decision → gaps → interventions |
| John's next care manager starts from scratch | Unified profile persists, summary cached |

### Performance

| Step | Duration |
|------|----------|
| Search & UI load | ~1 second |
| Data fetch from DynamoDB & profile assembly | ~2-5 seconds |
| Bedrock AI analysis & recommendations | ~5-15 seconds |
| Workflow triggers (SMS, tasks, alerts) | ~5-10 seconds |
| **Total end-to-end** | **~15-30 seconds** |

---

## Business Impact

| Metric | Before | After |
|--------|--------|-------|
| Time to build member picture | 20-30 minutes | 15-30 seconds |
| Care gaps detected | Manual review | Automatic AI detection |
| Follow-up actions | Manual coordination | Auto-triggered workflows |
| Audit trail | Fragmented / none | Full AI decision logging |
| Systems accessed | 4-5 separate tools | 1 unified portal |

---

## Definition of Done

| Criteria | Target |
|----------|--------|
| Unified profile built in real time | ✅ Under 30 seconds |
| AI recommends next-best actions | ✅ Ranked, explainable |
| Workflows triggered automatically | ✅ SMS, tasks, alerts via SNS |
| End-to-end execution time | ✅ Under 3 minutes |
| Audit trail for compliance | ✅ All decisions + chat history logged |
| Streaming response to care manager | ✅ Bedrock streams via invoke_model_with_response_stream |
| Chat history with conversation context | ✅ Follow-up questions use prior context |
| Smart caching (skip Bedrock if unchanged) | ✅ Source data staleness detection |

---

## Engineering Tasks

| # | Task | Status | Description |
|---|------|--------|-------------|
| 1 | Build mock datasets | ✅ Done | 20 members, 58 claims, 44 pharmacy, 42 events, 40 conditions, 23 providers |
| 2 | Create data ingestion pipeline | ✅ Done | S3 + Lambda ETL + DynamoDB (single-table design with sync/delete) |
| 3 | Configure Bedrock Agent | ✅ Done | Claude 3 Haiku with streaming, healthcare prompt, structured + conversational output |
| 4 | Implement orchestration workflows | ✅ Done | Step Functions 4-step pipeline (fetch → analyze → write → notify) with smart caching |
| 5 | Add chat history | ✅ Done | CHAT_HISTORY# records in DynamoDB, conversation context passed to Bedrock |
| 6 | Add downstream notifications | ✅ Done | 3 SNS topics (patient SMS, care team email, pharmacy alerts) |
| 7 | Build API layer | To Do | API Gateway + Profile API Lambda |
| 8 | Build Chat UI | To Do | React frontend served via CloudFront |
| 9 | End-to-end integration & demo | To Do | Full flow validation against Definition of Done |

---

## Cost Considerations

This architecture is **100% serverless** — you pay only for what you use:

- **Lambda:** Per-invocation pricing, no idle costs
- **DynamoDB:** On-demand capacity, scales to zero
- **Bedrock:** Per-token pricing, no model hosting fees
- **Step Functions:** Per-state-transition pricing
- **S3 + CloudFront:** Storage + transfer costs only

Estimated cost for a pilot with 1,000 member lookups/day: **~$200-500/month** (varies by Bedrock model selection and data volume).

---

## Security & Compliance

- All data encrypted at rest (S3, DynamoDB) and in transit (TLS)
- IAM least-privilege access across all services
- PHI stays within the AWS boundary (Bedrock processes data in-region)
- Full audit trail in DynamoDB for every AI decision and action
- API Gateway throttling and authentication
- Compatible with HIPAA-eligible AWS services

---

## Why Rackspace

| Capability | What Rackspace Brings |
|------------|----------------------|
| AWS Expertise | Deep bench of certified AWS architects and engineers — we've built production healthcare workloads on AWS at scale |
| Healthcare Domain Knowledge | Experience with HIPAA-compliant architectures, PHI handling, and payer/provider workflows |
| Managed Services | Ongoing operational support — monitoring, incident response, cost optimization — so your team focuses on care, not infrastructure |
| Security & Compliance | Built-in security posture management, encryption, IAM governance, and audit readiness from day one |
| Speed to Production | Proven accelerators and reference architectures that compress timelines from months to weeks |
| AI/ML Practice | Hands-on Bedrock and generative AI experience — prompt engineering, agent configuration, and LLM optimization for healthcare use cases |

Rackspace doesn't just design the architecture — we build it, run it, and optimize it alongside your team.

---

## Speed to Value — Rapid Prototype to Production

This solution is designed for fast iteration with a clear path from prototype to production:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  WEEK 1-2    │    │  WEEK 3-4    │    │  WEEK 5-6    │    │  WEEK 7-8    │
│  Discovery   │───►│  Prototype   │───►│  Pilot       │───►│  Production  │
│              │    │              │    │              │    │              │
│ • Align on   │    │ • Mock data  │    │ • Real data  │    │ • Full       │
│   use cases  │    │ • Core API   │    │   integration│    │   deployment │
│ • Data model │    │ • Bedrock    │    │ • Care team  │    │ • Monitoring │
│ • Architecture│   │   agent      │    │   UAT        │    │ • Handoff    │
│   sign-off   │    │ • Working    │    │ • Security   │    │ • Ongoing    │
│              │    │   demo       │    │   review     │    │   support    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
     DESIGN            BUILD              VALIDATE           LAUNCH
```

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Discovery | 1-2 weeks | Signed-off architecture, data model, and use case alignment |
| Prototype | 2 weeks | Working demo with mock data — unified profile + AI recommendations + workflows |
| Pilot | 2 weeks | Real data integration, care team UAT, security review |
| Production | 1-2 weeks | Full deployment, monitoring, operational handoff |

**Total time to production: 6-8 weeks** — not months. The serverless architecture means zero infrastructure provisioning delays, and Rackspace accelerators compress the build phase significantly.

---

## Next Steps

1. **Approve architecture** and allocate team resources
2. **Set up AWS environment** (accounts, IAM roles, networking)
3. **Sprint 1:** Mock datasets + unified profile API
4. **Sprint 2:** Bedrock agent configuration + Step Functions workflows
5. **Sprint 3:** UI build + end-to-end integration
6. **Sprint 4:** Testing, security review, and demo

---

*This document describes the proposed architecture for the Unified Member Experience Orchestration Agent. For questions or feedback, please reach out to the engineering team.*
