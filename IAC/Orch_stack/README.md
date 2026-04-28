# Infrastructure as Code — Orchestration Stack

## Overview

Step Functions + Bedrock + Lambda orchestration for the Unified Member Experience Agent.

```
Input: { "memberId": "M-10042" }
         │
         ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Step 1: Fetch   │───►│  Step 2: Analyze  │───►│  Step 3: Write   │
│  (Lambda)        │    │  (Lambda+Bedrock) │    │  (Lambda)        │
│                  │    │                   │    │                  │
│  Query DynamoDB  │    │  Send to Claude   │    │  AI Decision     │
│  Assemble profile│    │  Get analysis     │    │  Care Gaps       │
│                  │    │  Get care gaps    │    │  Interventions   │
│                  │    │  Get actions      │    │  Summary         │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
                                                   DynamoDB
                                                (results stored)
```

## Prerequisites

1. Data Stack deployed (`IAC/Data_stack/`)
2. Mock data uploaded to DynamoDB
3. Bedrock model access enabled for `anthropic.claude-3-haiku-20240307-v1:0` in us-east-1

## Deployment

```bash
# 1. Get DynamoDB ARN from Data Stack
cd ../Data_stack
DYNAMO_ARN=$(terraform output -raw dynamodb_table_arn)

# 2. Deploy Orch Stack
cd ../Orch_stack
terraform init
terraform apply -var="dynamodb_table_arn=$DYNAMO_ARN"

# 3. Test with John Smith
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw step_function_arn) \
  --input '{"memberId":"M-10042"}'
```

## Teardown

```bash
terraform destroy -var="dynamodb_table_arn=$DYNAMO_ARN"
```
