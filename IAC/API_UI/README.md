# Infrastructure as Code — API + Auth Stack

## Overview

Cognito authentication + API Gateway + Lambda for the chat agent interface.

```
Sarah (browser)
    │
    ├── Sign up (email + password) → Cognito User Pool
    ├── Login → gets JWT token
    │
    ▼
API Gateway (JWT auth via Cognito)
    │
    ├── POST /chat          → Lambda → Step Functions → Bedrock → response
    ├── GET  /chat          → Lambda → DynamoDB → chat history
    ├── GET  /members       → Lambda → DynamoDB → search results
    └── GET  /members/profile → Lambda → DynamoDB → full profile
```

## Prerequisites

1. Data Stack deployed (`IAC/Data_stack/`)
2. Orch Stack deployed (`IAC/Orch_stack/`)

## Deployment

```bash
# Get ARNs from other stacks
cd ../Data_stack
DYNAMO_ARN=$(terraform output -raw dynamodb_table_arn)

cd ../Orch_stack
SFN_ARN=$(terraform output -raw step_function_arn)

# Deploy API stack
cd ../API_UI
terraform init
terraform apply -var="dynamodb_table_arn=$DYNAMO_ARN" -var="step_function_arn=$SFN_ARN"
```

## Test Flow

```bash
# 1. Sign up Sarah
aws cognito-idp sign-up \
  --client-id $(terraform output -raw cognito_client_id) \
  --username sarah@example.com \
  --password TestPass123 \
  --user-attributes Name=name,Value=Sarah Name=email,Value=sarah@example.com

# 2. Confirm (admin bypass)
aws cognito-idp admin-confirm-sign-up \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username sarah@example.com

# 3. Login (get token)
TOKEN=$(aws cognito-idp initiate-auth \
  --client-id $(terraform output -raw cognito_client_id) \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=sarah@example.com,PASSWORD=TestPass123 \
  --query 'AuthenticationResult.IdToken' --output text)

# 4. Chat with the agent
curl -X POST $(terraform output -raw api_url)/chat \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"memberId":"M-10042","message":"Tell me about this member"}'

# 5. Get chat history
curl $(terraform output -raw api_url)/chat?memberId=M-10042 \
  -H "Authorization: $TOKEN"

# 6. Search members
curl "$(terraform output -raw api_url)/members?search=John+Smith" \
  -H "Authorization: $TOKEN"
```

## Teardown

```bash
terraform destroy -var="dynamodb_table_arn=$DYNAMO_ARN" -var="step_function_arn=$SFN_ARN"
```
