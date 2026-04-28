# Mock Data Strategy — Unified Member Experience Orchestration Agent

## Overview

This document defines the mock datasets required to demonstrate the full end-to-end flow of the Unified Member Experience Agent — from raw data ingestion (S3) through processing (Lambda) to real-time profile assembly (DynamoDB) and AI-driven recommendations (Bedrock).

The mock data is designed to cover realistic healthcare scenarios that showcase every capability of the system.

---

## Data Generation Approach

```
┌─────────────────────────────────────────────────────────────────┐
│                    MOCK DATA PIPELINE                            │
│                                                                  │
│  Step 1: Generate       Step 2: Upload       Step 3: Process     │
│  raw files              to S3                via Lambda ETL       │
│                                                                  │
│  ┌──────────┐          ┌──────────┐         ┌──────────────┐    │
│  │ CSV/JSON  │────────►│ S3 Data  │────────►│ Lambda ETL    │    │
│  │ Generator │          │ Lake     │         │ (Transform +  │    │
│  │ (Script)  │          │          │         │  Normalize)   │    │
│  └──────────┘          └──────────┘         └──────┬───────┘    │
│                                                     │            │
│                                              Step 4: Write       │
│                                              to DynamoDB         │
│                                                     │            │
│                                              ┌──────▼───────┐   │
│                                              │ DynamoDB      │   │
│                                              │ (Query-ready  │   │
│                                              │  records)     │   │
│                                              └──────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

**Key behavior:** When a file is overwritten in S3, Lambda triggers automatically, upserts all records, and deletes any records from DynamoDB that no longer exist in the source file — keeping DynamoDB as an exact mirror of S3.

---

## S3 Bucket Structure

```
s3://member-experience-data-lake/
│
├── raw/
│   ├── members/
│   │   └── member_enrollment.csv          (20 members + patient clinical fields)
│   │
│   ├── claims/
│   │   └── claims_2026_q1.csv             (58 claims across all members)
│   │
│   ├── pharmacy/
│   │   └── pharmacy_feed_apr_2026.json    (44 prescriptions)
│   │
│   ├── care-events/
│   │   └── encounters_2026.fhir.json      (42 encounters)
│   │
│   ├── providers/
│   │   └── provider_directory.csv          (23 providers)
│   │
│   └── conditions/
│       └── conditions.json                 (40 conditions)
│
├── processed/
│   └── (Lambda archives processed files here)
│
└── static/
    └── (UI assets served via CloudFront)
```

---

## Mock Dataset Definitions

### 1. Members + Patients (Payer + Clinical Side)

**File:** `raw/members/member_enrollment.csv`
**Format:** CSV
**Records:** 20 members

One file produces two DynamoDB record types per member:
- `MEMBER#` — payer/insurance fields
- `PATIENT#` — clinical fields

| Field | Type | Example | Side | Description |
|-------|------|---------|------|-------------|
| memberId | String | M-10042 | Payer | Unique member identifier |
| firstName | String | John | Payer | First name |
| lastName | String | Smith | Payer | Last name |
| dob | Date | 1968-03-15 | Payer | Date of birth |
| gender | String | Male | Payer | Gender |
| planName | String | Gold PPO | Payer | Insurance plan |
| planType | String | PPO | Payer | Plan type |
| coverageStatus | String | Active | Payer | Active / Inactive |
| enrollmentDate | Date | 2019-06-01 | Payer | Plan enrollment date |
| state | String | TX | Payer | State of residence |
| pcpId | String | PRV-201 | Clinical | Assigned PCP provider ID |
| livingSituation | String | Alone | Clinical | Alone / With family / Assisted |
| riskScore | Number | 92 | Clinical | AI-calculated risk (0-100) |
| allergies | String | Penicillin;Sulfa | Clinical | Semicolon-separated, "None" if none |
| bloodType | String | A+ | Clinical | Blood type |
| bmi | Number | 31.2 | Clinical | Body mass index |
| smokingStatus | String | Former | Clinical | Current / Former / Never |
| preferredLanguage | String | English | Clinical | Preferred language |

**Sample Records:**

```csv
memberId,firstName,lastName,dob,gender,planName,planType,coverageStatus,enrollmentDate,pcpId,state,livingSituation,riskScore,allergies,bloodType,bmi,smokingStatus,preferredLanguage
M-10042,John,Smith,1968-03-15,Male,Gold PPO,PPO,Active,2019-06-01,PRV-201,TX,Alone,92,"Penicillin;Sulfa",A+,31.2,Former,English
M-10043,Maria,Garcia,1975-08-22,Female,Silver HMO,HMO,Active,2020-01-15,PRV-205,CA,With family,78,"None",O+,27.8,Never,Spanish
M-10044,Robert,Chen,1959-11-03,Male,Gold PPO,PPO,Active,2018-09-10,PRV-208,NY,Alone,85,"Aspirin",B+,29.5,Never,English
M-10052,Thomas,Anderson,1962-10-28,Male,Gold PPO,PPO,Active,2018-03-15,PRV-201,TX,With family,94,"None",O+,32.4,Current,English
M-10054,Richard,Lee,1950-06-22,Male,Platinum PPO,PPO,Active,2015-01-10,PRV-218,PA,Assisted,96,"Penicillin;Contrast dye",A+,26.9,Former,English
M-10059,Dorothy,Walker,1947-03-25,Female,Platinum PPO,PPO,Active,2014-05-20,PRV-208,NY,Assisted,98,"Penicillin;ACE inhibitors;Shellfish",O-,21.5,Former,English
```

**All 20 members:** M-10042 through M-10060 (see full file in `IAC/Data_stack/mock-data/members/`)


---

### 2. Conditions (Clinical)

**File:** `raw/conditions/conditions.json`
**Format:** JSON
**Records:** 40 conditions across all members with diagnoses

| Field | Type | Example | Description |
|-------|------|---------|-------------|
| conditionId | String | CND-60001 | Unique condition ID |
| memberId | String | M-10042 | Member reference |
| diagnosis | String | Type 2 Diabetes Mellitus | Human-readable condition name |
| icdCode | String | E11 | ICD-10 code family |
| onsetDate | Date | 2021-06-15 | When first diagnosed |
| status | String | Active | Active / Resolved / Managed |
| severity | String | Uncontrolled | Controlled / Uncontrolled / Managed / Severe / Post-surgical / Episodic |
| lastAssessedDate | Date | 2026-04-12 | Last clinical assessment |

**Sample Records:**

```json
[
  {
    "conditionId": "CND-60001",
    "memberId": "M-10042",
    "diagnosis": "Type 2 Diabetes Mellitus",
    "icdCode": "E11",
    "onsetDate": "2021-06-15",
    "status": "Active",
    "severity": "Uncontrolled",
    "lastAssessedDate": "2026-04-12"
  },
  {
    "conditionId": "CND-60002",
    "memberId": "M-10042",
    "diagnosis": "Essential Hypertension",
    "icdCode": "I10",
    "onsetDate": "2018-03-20",
    "status": "Active",
    "severity": "Managed",
    "lastAssessedDate": "2025-12-10"
  },
  {
    "conditionId": "CND-60090",
    "memberId": "M-10054",
    "diagnosis": "Cerebral Infarction (Stroke)",
    "icdCode": "I63.9",
    "onsetDate": "2026-03-30",
    "status": "Active",
    "severity": "Post-acute",
    "lastAssessedDate": "2026-04-05"
  },
  {
    "conditionId": "CND-60130",
    "memberId": "M-10059",
    "diagnosis": "Acute on Chronic Systolic Heart Failure",
    "icdCode": "I50.23",
    "onsetDate": "2020-03-15",
    "status": "Active",
    "severity": "Severe",
    "lastAssessedDate": "2026-03-25"
  }
]
```

**Full conditions by member:** (see complete file in `IAC/Data_stack/mock-data/conditions/`)

| Member | Conditions |
|--------|-----------|
| John Smith (M-10042) | Type 2 Diabetes (Uncontrolled), Hypertension (Managed) |
| Maria Garcia (M-10043) | COPD (Uncontrolled) |
| Robert Chen (M-10044) | Osteoarthritis Right Knee (Post-surgical), Type 2 Diabetes (Controlled) |
| Linda Johnson (M-10045) | Gestational Diabetes (Diet-controlled) |
| James Williams (M-10046) | Atherosclerotic Heart Disease (Managed), Hypertension (Controlled) |
| Patricia Brown (M-10047) | Alzheimer's (Moderate), Hypertension (Managed), Hip Fracture (Post-surgical) |
| Susan Davis (M-10049) | Heart Failure (Uncontrolled), Type 2 Diabetes (Managed), CKD Stage 3 (Stable), Hypertension (Managed) |
| Michael Wilson (M-10050) | Major Depression (Moderate), GERD (Moderate) |
| Thomas Anderson (M-10052) | STEMI Heart Attack (Post-acute), Atherosclerotic Heart Disease (Managed), Hypertension (Managed) |
| Angela Robinson (M-10053) | Anxiety (Moderate), Depression (Moderate) |
| Richard Lee (M-10054) | Stroke (Post-acute), Atrial Fibrillation (Uncontrolled), CKD Stage 4 (Progressive), Hypertension (Managed) |
| Karen White (M-10055) | Hypothyroidism (Controlled), Osteoporosis (Managed), Anxiety (Mild) |
| Barbara Clark (M-10057) | Type 2 Diabetes (Uncontrolled), Heart Failure (Uncontrolled), Atrial Fibrillation (Managed) |
| Christopher Lewis (M-10058) | Hypertension (Controlled), Hyperlipidemia (Controlled) |
| Dorothy Walker (M-10059) | Heart Failure (Severe, EF 25%), CKD Stage 5 (Severe), Chronic AFib (Managed), Hypertension (Managed) |
| Kevin Hall (M-10060) | GERD (Moderate), Migraine (Episodic) |

**Members with no conditions:** David Martinez (M-10048), Daniel Harris (M-10056), Jennifer Taylor (M-10051) — healthy/low-utilization

---

### 3. Claims

**File:** `raw/claims/claims_2026_q1.csv`
**Format:** CSV
**Records:** 58 claims across all 20 members

| Field | Type | Example | Description |
|-------|------|---------|-------------|
| claimId | String | CLM-50001 | Unique claim ID |
| memberId | String | M-10042 | Member reference |
| claimType | String | Emergency | Emergency / Inpatient / Outpatient / Professional |
| diagnosisCode | String | E11.65 | ICD-10 code |
| diagnosisDesc | String | Type 2 diabetes with hyperglycemia | Human-readable diagnosis |
| providerId | String | PRV-301 | Treating provider |
| facilityName | String | Memorial Hermann ER | Facility name |
| serviceDate | Date | 2026-01-18 | Date of service |
| paidAmount | Number | 4250.00 | Amount paid |
| status | String | Paid | Paid / Pending / Denied |

**Sample Records:**

```csv
claimId,memberId,claimType,diagnosisCode,diagnosisDesc,providerId,facilityName,serviceDate,paidAmount,status
CLM-50001,M-10042,Emergency,E11.65,Type 2 diabetes with hyperglycemia,PRV-301,Memorial Hermann ER,2026-01-18,4250.00,Paid
CLM-50090,M-10052,Emergency,I21.3,ST elevation myocardial infarction of unspecified site,PRV-301,Memorial Hermann ER,2026-03-15,15200.00,Paid
CLM-50091,M-10052,Inpatient,I21.3,ST elevation myocardial infarction of unspecified site,PRV-301,Memorial Hermann Hospital,2026-03-15,48000.00,Paid
CLM-50110,M-10054,Inpatient,J18.9,Pneumonia unspecified organism,PRV-218,Cooper Medical Associates Hospital,2026-01-25,18500.00,Paid
CLM-50111,M-10054,Emergency,I63.9,Cerebral infarction unspecified,PRV-218,Cooper Medical Associates ER,2026-03-30,9800.00,Paid
CLM-50160,M-10059,Inpatient,I50.23,Acute on chronic systolic heart failure,PRV-208,Wong Internal Medicine Hospital,2026-01-10,22000.00,Paid
```

---

### 4. Pharmacy

**File:** `raw/pharmacy/pharmacy_feed_apr_2026.json`
**Format:** JSON
**Records:** 44 prescriptions across all members with conditions

| Field | Type | Example | Description |
|-------|------|---------|-------------|
| rxId | String | RX-70001 | Unique prescription ID |
| memberId | String | M-10042 | Member reference |
| medication | String | Insulin Glargine | Drug name |
| dosage | String | 100 units/mL | Dosage |
| prescriberId | String | PRV-201 | Prescribing provider |
| pharmacyName | String | CVS #4521 Main St | Dispensing pharmacy |
| lastRefillDate | Date | 2026-03-13 | Last refill date |
| daysSupply | Number | 30 | Days supply per refill |
| refillsRemaining | Number | 3 | Refills left |
| adherencePercent | Number | 58 | Medication adherence (PDC %) |
| status | String | Overdue | Active / Overdue / Discontinued |

**Sample Records:**

```json
[
  {
    "rxId": "RX-70001",
    "memberId": "M-10042",
    "medication": "Insulin Glargine",
    "dosage": "100 units/mL",
    "prescriberId": "PRV-201",
    "pharmacyName": "CVS #4521 Main St",
    "lastRefillDate": "2026-03-13",
    "daysSupply": 30,
    "refillsRemaining": 3,
    "adherencePercent": 58,
    "status": "Overdue"
  },
  {
    "rxId": "RX-70093",
    "memberId": "M-10052",
    "medication": "Lisinopril",
    "dosage": "20mg",
    "prescriberId": "PRV-201",
    "pharmacyName": "CVS #4521 Main St",
    "lastRefillDate": "2026-03-25",
    "daysSupply": 30,
    "refillsRemaining": 4,
    "adherencePercent": 72,
    "status": "Overdue"
  },
  {
    "rxId": "RX-70150",
    "memberId": "M-10059",
    "medication": "Furosemide",
    "dosage": "80mg",
    "prescriberId": "PRV-208",
    "pharmacyName": "Rite Aid #3301",
    "lastRefillDate": "2026-03-15",
    "daysSupply": 30,
    "refillsRemaining": 2,
    "adherencePercent": 60,
    "status": "Overdue"
  }
]
```

---

### 5. Care Events

**File:** `raw/care-events/encounters_2026.fhir.json`
**Format:** JSON (simplified FHIR-like structure)
**Records:** 42 encounters across all members

| Field | Type | Example | Description |
|-------|------|---------|-------------|
| eventId | String | EVT-80001 | Unique event ID |
| memberId | String | M-10042 | Member reference |
| eventType | String | ER_Visit | ER_Visit / Inpatient / Outpatient / Missed_Appointment / Lab_Result / Discharge |
| providerId | String | PRV-301 | Provider involved |
| facilityName | String | Memorial Hermann ER | Facility |
| date | Date | 2026-01-18 | Event date |
| diagnosisCode | String | E11.65 | ICD-10 code (null for missed appointments) |
| outcome | String | Discharged | Discharged / Admitted / Completed / No_Show |
| notes | String | Patient presented with... | Clinical notes |

**Sample Records:**

```json
[
  {
    "eventId": "EVT-80001",
    "memberId": "M-10042",
    "eventType": "ER_Visit",
    "providerId": "PRV-301",
    "facilityName": "Memorial Hermann ER",
    "date": "2026-01-18",
    "diagnosisCode": "E11.65",
    "outcome": "Discharged",
    "notes": "Patient presented with hyperglycemia. Blood glucose 380 mg/dL. Stabilized and discharged with instructions to follow up with PCP."
  },
  {
    "eventId": "EVT-80093",
    "memberId": "M-10052",
    "eventType": "Missed_Appointment",
    "providerId": "PRV-201",
    "facilityName": "Dr. Patel Family Medicine",
    "date": "2026-03-26",
    "diagnosisCode": null,
    "outcome": "No_Show",
    "notes": "Missed 1-week post-MI PCP follow-up. Critical: needs medication reconciliation and cardiac rehab enrollment."
  },
  {
    "eventId": "EVT-80133",
    "memberId": "M-10059",
    "eventType": "Missed_Appointment",
    "providerId": "PRV-208",
    "facilityName": "Wong Internal Medicine",
    "date": "2026-04-15",
    "diagnosisCode": null,
    "outcome": "No_Show",
    "notes": "Missed nephrology referral appointment. Critical: CKD stage 5 needs dialysis evaluation. Patient in assisted living, transportation barrier."
  }
]
```

---

### 6. Providers

**File:** `raw/providers/provider_directory.csv`
**Format:** CSV
**Records:** 23 providers

| Field | Type | Example | Description |
|-------|------|---------|-------------|
| providerId | String | PRV-201 | Unique provider ID |
| name | String | Dr. Anita Patel | Provider name |
| specialty | String | Family Medicine | Specialty |
| facilityName | String | Patel Family Medicine | Practice/facility |
| npi | String | 1234567890 | National Provider Identifier |
| phone | String | 713-555-0142 | Contact number |
| state | String | TX | State |
| inNetwork | Boolean | true | In-network status |

**Specialties covered:** Family Medicine, Internal Medicine, Cardiology, Geriatrics, Endocrinology, Emergency Medicine, Orthopedic Surgery, Nephrology, Pulmonology, Psychiatry, OB/GYN, Neurology, Gastroenterology, Cardiac Rehabilitation, Physical Therapy

**Sample Records:**

```csv
providerId,name,specialty,facilityName,npi,phone,state,inNetwork
PRV-201,Dr. Anita Patel,Family Medicine,Patel Family Medicine,1234567890,713-555-0142,TX,true
PRV-225,Dr. Miguel Rivera,Endocrinology,Rivera Endocrinology,1234567899,713-555-0199,TX,true
PRV-340,Dr. Kevin Park,Nephrology,Cooper Nephrology Associates,2345678906,215-555-0250,PA,true
PRV-344,Dr. Robert Kim,Neurology,Cooper Neurology Associates,2345678910,215-555-0280,PA,true
PRV-346,Dr. David Nguyen,Cardiac Rehabilitation,Memorial Hermann Cardiac Rehab,2345678912,713-555-0400,TX,true
```

---

## Demo Scenarios

Each mock member is designed to showcase a different capability of the system:

| Member | Risk | Scenario | What It Demonstrates |
|--------|------|----------|---------------------|
| **John Smith (M-10042)** | 92 | Uncontrolled diabetes, medication non-adherence, missed specialist visits, lives alone | Full profile assembly, AI risk analysis, multi-intervention triggering, talking points |
| **Maria Garcia (M-10043)** | 78 | COPD with frequent ER visits, inhaler non-adherence | Respiratory care gaps, pharmacy alerts, readmission risk |
| **Robert Chen (M-10044)** | 85 | Post knee replacement, diabetic, on blood thinners, lives alone | Post-surgical care gaps, multi-condition risk, home support assessment |
| **Linda Johnson (M-10045)** | 45 | Pregnant with gestational diabetes, diet-controlled | Prenatal care tracking, gestational condition management |
| **James Williams (M-10046)** | 55 | Heart disease + hypertension, stable but needs monitoring | Low-risk profile, preventive care recommendations |
| **Patricia Brown (M-10047)** | 88 | Alzheimer's, hip fracture, assisted living | Geriatric care complexity, fall risk, facility coordination |
| **David Martinez (M-10048)** | 12 | Young, healthy, minimal history | Low-utilization baseline, wellness program |
| **Susan Davis (M-10049)** | 90 | Heart failure + CKD + diabetes, lives alone | Multi-chronic complexity, social determinants |
| **Michael Wilson (M-10050)** | 48 | Depression + GERD, missed mental health follow-up | Behavioral health gaps, medication adherence |
| **Jennifer Taylor (M-10051)** | 15 | Young, healthy, back pain only | Low-risk, routine care |
| **Thomas Anderson (M-10052)** | 94 | Post heart attack, missed critical PCP follow-up | Post-MI care gaps, cardiac rehab enrollment |
| **Angela Robinson (M-10053)** | 42 | Anxiety + depression, declining medication adherence | Mental health gaps, therapy referral |
| **Richard Lee (M-10054)** | 96 | Stroke + AFib + CKD stage 4, assisted living | Highest complexity, transportation barriers |
| **Karen White (M-10055)** | 35 | Hypothyroidism + osteoporosis + anxiety, stable | Multi-condition but well-managed |
| **Daniel Harris (M-10056)** | 8 | Young, healthy, wellness visit only | Lowest risk baseline |
| **Barbara Clark (M-10057)** | 91 | Diabetes + heart failure + AFib, lives alone | Insulin adherence issues, isolation risk |
| **Christopher Lewis (M-10058)** | 30 | Hypertension + high cholesterol, well-managed | Compliant patient, routine monitoring |
| **Dorothy Walker (M-10059)** | 98 | Heart failure EF 25% + CKD stage 5 + AFib, assisted living | Highest acuity, dialysis evaluation needed |
| **Kevin Hall (M-10060)** | 28 | GERD + migraines, moderate complexity | Moderate risk, GI referral |

---

## DynamoDB Table Design

### Table: `UnifiedMemberProfile`

**Partition Key:** `memberId`
**Sort Key:** `recordType#recordId`

This single-table design stores all entity types for a member together for fast retrieval:

| memberId | recordType#recordId | Data |
|----------|-------------------|------|
| M-10042 | MEMBER#M-10042 | {name, dob, plan, coverage...} |
| M-10042 | PATIENT#M-10042 | {riskScore: 92, allergies: ["Penicillin","Sulfa"], bmi: 31.2...} |
| M-10042 | CONDITION#CND-60001 | {diagnosis: "Type 2 Diabetes", severity: "Uncontrolled"...} |
| M-10042 | CONDITION#CND-60002 | {diagnosis: "Hypertension", severity: "Managed"...} |
| M-10042 | CLAIM#CLM-50001 | {type: "Emergency", diagnosis: "E11.65", amount: 4250...} |
| M-10042 | PHARMACY#RX-70001 | {medication: "Insulin Glargine", adherence: 58%...} |
| M-10042 | PHARMACY#RX-70002 | {medication: "Metformin", adherence: 62%...} |
| M-10042 | PHARMACY#RX-70003 | {medication: "Lisinopril", adherence: 85%...} |
| M-10042 | CARE_EVENT#EVT-80001 | {type: "ER_Visit", date: "2026-01-18"...} |
| M-10042 | CARE_EVENT#EVT-80003 | {type: "Missed_Appointment"...} |
| M-10042 | AI_DECISION#D-88421 | {analysis: "...", actions: [...], confidence: 0.94} |
| M-10042 | INTERVENTION#INT-90001 | {type: "SMS", status: "Delivered"...} |
| M-10042 | CARE_GAP#GAP-40001 | {type: "Insulin refill overdue", status: "Open"...} |
| M-10042 | CARE_PLAN#PLN-10001 | {program: "Diabetes Management", status: "Eligible"...} |
| M-10042 | SUMMARY#SUM-20001 | {summaryText: "...", talkingPoints: [...]...} |

**Query pattern:** `memberId = "M-10042"` → returns ALL records for John Smith in one query (~5ms).

**Filter by type:** `memberId = "M-10042" AND begins_with(recordType, "CLAIM")` → returns only claims.

### Global Secondary Index: `recordType-index`

**Partition Key:** `gsiRecordType`
**Sort Key:** `memberId`

Enables cross-member queries like "show all open CARE_GAP records" or "all overdue PHARMACY records."

---

## Lambda ETL Processing Flow

How raw data in S3 becomes query-ready records in DynamoDB:

```
┌─────────────────────────────────────────────────────────────┐
│                    LAMBDA ETL PIPELINE                       │
│                                                              │
│  1. TRIGGER                                                  │
│     S3 Event Notification → Lambda                           │
│     (new file uploaded/overwritten in raw/ prefix)           │
│                                                              │
│  2. READ & PARSE                                             │
│     Lambda reads file from S3                                │
│     Detects data type from prefix:                           │
│       raw/members/    → MEMBER + PATIENT                     │
│       raw/claims/     → CLAIM                                │
│       raw/pharmacy/   → PHARMACY                             │
│       raw/care-events/→ CARE_EVENT                           │
│       raw/providers/  → PROVIDER                             │
│       raw/conditions/ → CONDITION                            │
│     Parses CSV or JSON format                                │
│                                                              │
│  3. TRANSFORM                                                │
│     Members split into MEMBER + PATIENT records              │
│     Allergies parsed from semicolon-separated to list        │
│     All records tagged with gsiRecordType + updatedAt        │
│                                                              │
│  4. WRITE TO DYNAMODB (Upsert)                               │
│     Batch write using single-table design                    │
│     memberId as PK, recordType#recordId as SK                │
│     Existing records updated, new records inserted           │
│                                                              │
│  5. SYNC (Delete Stale Records)                              │
│     Query GSI for all existing records of this type          │
│     Compare against new file's record keys                   │
│     Delete any DynamoDB records not in the new file          │
│     → DynamoDB becomes exact mirror of S3                    │
│                                                              │
│  6. ARCHIVE                                                  │
│     Copy processed file to processed/ prefix in S3           │
│     Log processing stats to CloudWatch                       │
└─────────────────────────────────────────────────────────────┘
```

---

## How Mock Data Powers Each Demo Step

| Demo Step | Mock Data Used | Source |
|-----------|---------------|--------|
| Sarah searches for John Smith | MEMBER + PATIENT records | DynamoDB (pre-loaded via ETL) |
| System shows unified profile | All record types for M-10042 | DynamoDB single query |
| Active conditions displayed | CONDITION records (Type 2 Diabetes, Hypertension) | DynamoDB |
| Medications at risk shown | PHARMACY records (adherence%, status) | DynamoDB |
| AI analyzes context | Claims + Pharmacy + Care Events + Conditions + Patient | DynamoDB → passed to Bedrock |
| AI identifies care gaps | Pharmacy (adherence%), Care Events (missed appts), Conditions (severity) | Bedrock analyzes, writes Care Gap records |
| Workflows trigger | AI Decision actions[] | Step Functions reads decision, fires Lambdas |
| Sarah sees summary + talking points | Member Summary (talkingPoints, riskAssessment) | DynamoDB (generated by Bedrock, cached) |
| Audit trail | AI Decision + Intervention records | DynamoDB (immutable log) |

---

## Data Volume Summary

| Entity | File | Records | Notes |
|--------|------|---------|-------|
| Members | member_enrollment.csv | 20 | Payer fields → MEMBER# records |
| Patients | member_enrollment.csv | 20 | Clinical fields → PATIENT# records (same source file) |
| Conditions | conditions.json | 40 | 0-4 per member depending on health status |
| Claims | claims_2026_q1.csv | 58 | 1-5 per member depending on utilization |
| Pharmacy | pharmacy_feed_apr_2026.json | 44 | 0-4 medications per member |
| Care Events | encounters_2026.fhir.json | 42 | ER visits, inpatient, outpatient, missed appts, labs, discharges |
| Providers | provider_directory.csv | 23 | PCPs, specialists, ER staff, surgeons, rehab |
| Care Gaps | Generated at runtime | — | Created by Bedrock during demo |
| AI Decisions | Generated at runtime | — | Created by Bedrock during demo |
| Interventions | Generated at runtime | — | Created by Step Functions during demo |
| Summaries | Generated at runtime | — | Created by Bedrock during demo |

**Total static mock records: ~247**
**DynamoDB records after ETL: ~267** (members produce 2 records each: MEMBER + PATIENT)
**Runtime-generated records: Created live during demo**

---

*This document defines the mock data strategy for the Unified Member Experience Orchestration Agent. All sample data uses fictional names and identifiers for demonstration purposes only.*
