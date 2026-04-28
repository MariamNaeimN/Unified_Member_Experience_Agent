# Infrastructure as Code — Data Stack

## Overview

Terraform infrastructure for the Unified Member Experience Orchestration Agent data layer. This stack provisions the foundational data services that power the mock data pipeline:

```
S3 (Data Lake) → Lambda (ETL) → DynamoDB (Unified Profile)
```

## Stack Components

| Component | Resource | Purpose |
|-----------|----------|---------|
| S3 Data Lake | `aws_s3_bucket` | Raw data ingestion + processed archive + static UI assets |
| DynamoDB | `aws_dynamodb_table` | Single-table design for unified member profiles |
| Lambda ETL | `aws_lambda_function` | Transforms raw S3 files into DynamoDB records |
| IAM Roles | `aws_iam_role` | Least-privilege access for Lambda |
| S3 Notifications | `aws_s3_bucket_notification` | Triggers Lambda on new file uploads/overwrites |
| CloudWatch | `aws_cloudwatch_log_group` | Lambda execution logs |

## File Structure

```
Data_stack/
├── README.md
├── main.tf                  # Provider config + backend
├── variables.tf             # Input variables
├── terraform.tfvars         # Default variable values for dev
├── outputs.tf               # Stack outputs
├── .gitignore               # Excludes .terraform/, .build/, state files
├── s3.tf                    # S3 data lake bucket + triggers
├── dynamodb.tf              # DynamoDB unified profile table
├── lambda-etl.tf            # Lambda ETL function (member/patient split, sync/delete)
├── iam.tf                   # IAM roles and policies
├── mock-data/               # Mock data files (6 files, 247 records)
│   ├── members/
│   │   └── member_enrollment.csv       (20 members + patient clinical fields)
│   ├── claims/
│   │   └── claims_2026_q1.csv          (58 claims)
│   ├── pharmacy/
│   │   └── pharmacy_feed_apr_2026.json (44 prescriptions)
│   ├── care-events/
│   │   └── encounters_2026.fhir.json   (42 encounters)
│   ├── providers/
│   │   └── provider_directory.csv       (23 providers)
│   └── conditions/
│       └── conditions.json              (40 conditions)
└── scripts/
    └── upload-mock-data.sh  # Uploads mock data to S3 (triggers ETL)
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- AWS account with permissions for S3, DynamoDB, Lambda, IAM, CloudWatch

## Deployment

```bash
# 1. Navigate to the stack
cd IAC/Data_stack

# 2. Initialize Terraform
terraform init

# 3. Preview what will be created
terraform plan

# 4. Deploy (creates S3, DynamoDB, Lambda, IAM, CloudWatch)
terraform apply

# 5. Upload mock data to S3 (triggers Lambda ETL automatically)
chmod +x scripts/upload-mock-data.sh
./scripts/upload-mock-data.sh dev member-experience

# 6. Verify data loaded into DynamoDB
aws dynamodb scan \
  --table-name member-experience-unified-profile-dev \
  --select COUNT
```

Expected DynamoDB record count after ETL: ~267 (247 source records + 20 extra PATIENT records split from members).

## Teardown

```bash
# Destroy all resources (s3_force_destroy=true allows bucket deletion with objects)
terraform destroy
```

## Configuration

Default values are in `terraform.tfvars`:

| Variable | Default | Description |
|----------|---------|-------------|
| environment | dev | Environment name (dev/staging/prod) |
| project_name | member-experience | Used in all resource names |
| aws_region | us-east-1 | AWS region |
| s3_force_destroy | true | Allow bucket deletion with objects (dev only) |

Override for production:
```bash
terraform apply -var="environment=prod" -var="s3_force_destroy=false"
```

## ETL Behavior

- File uploaded to S3 `raw/` → Lambda triggers automatically
- File overwritten → Lambda re-processes, upserts records, deletes stale records
- Record removed from source file → Lambda deletes it from DynamoDB
- DynamoDB stays as an exact mirror of S3 source files
