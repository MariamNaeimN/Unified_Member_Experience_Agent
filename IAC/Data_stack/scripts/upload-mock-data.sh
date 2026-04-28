#!/bin/bash
# =============================================================================
# Upload mock data to S3 data lake
# Usage: ./scripts/upload-mock-data.sh <environment> <project_name>
# Example: ./scripts/upload-mock-data.sh dev member-experience
# =============================================================================

set -euo pipefail

ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${2:-member-experience}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOCK_DATA_DIR="${SCRIPT_DIR}/../mock-data"

# Get bucket name from Terraform output or construct it
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${PROJECT_NAME}-data-lake-${ENVIRONMENT}-${ACCOUNT_ID}"

echo "============================================="
echo "  Mock Data Upload"
echo "  Bucket: ${BUCKET_NAME}"
echo "  Environment: ${ENVIRONMENT}"
echo "============================================="

# Verify bucket exists
if ! aws s3 ls "s3://${BUCKET_NAME}" > /dev/null 2>&1; then
    echo "ERROR: Bucket ${BUCKET_NAME} does not exist."
    echo "Run 'terraform apply' first to create the infrastructure."
    exit 1
fi

# Upload members
echo ""
echo ">> Uploading members..."
aws s3 cp "${MOCK_DATA_DIR}/members/member_enrollment.csv" \
    "s3://${BUCKET_NAME}/raw/members/member_enrollment.csv"

# Upload claims
echo ">> Uploading claims..."
aws s3 cp "${MOCK_DATA_DIR}/claims/claims_2026_q1.csv" \
    "s3://${BUCKET_NAME}/raw/claims/claims_2026_q1.csv"

# Upload pharmacy
echo ">> Uploading pharmacy..."
aws s3 cp "${MOCK_DATA_DIR}/pharmacy/pharmacy_feed_apr_2026.json" \
    "s3://${BUCKET_NAME}/raw/pharmacy/pharmacy_feed_apr_2026.json"

# Upload care events
echo ">> Uploading care events..."
aws s3 cp "${MOCK_DATA_DIR}/care-events/encounters_2026.fhir.json" \
    "s3://${BUCKET_NAME}/raw/care-events/encounters_2026.fhir.json"

# Upload providers
echo ">> Uploading providers..."
aws s3 cp "${MOCK_DATA_DIR}/providers/provider_directory.csv" \
    "s3://${BUCKET_NAME}/raw/providers/provider_directory.csv"

# Upload conditions
echo ">> Uploading conditions..."
aws s3 cp "${MOCK_DATA_DIR}/conditions/conditions.json" \
    "s3://${BUCKET_NAME}/raw/conditions/conditions.json"

echo ""
echo "============================================="
echo "  Upload complete!"
echo "  Files uploaded to s3://${BUCKET_NAME}/raw/"
echo ""
echo "  Lambda ETL will automatically process"
echo "  each file and write to DynamoDB."
echo ""
echo "  Check processing logs:"
echo "  aws logs tail /aws/lambda/${PROJECT_NAME}-etl-processor-${ENVIRONMENT} --follow"
echo "============================================="
