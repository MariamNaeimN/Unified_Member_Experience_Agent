#!/bin/bash
# =============================================================================
# Verify member data consistency in DynamoDB
# Usage: ./scripts/verify-member-data.sh <environment> <project_name> <member_id>
# Example: ./scripts/verify-member-data.sh dev member-experience M-10042
# =============================================================================

set -euo pipefail

ENVIRONMENT="${1:-dev}"
PROJECT_NAME="${2:-member-experience}"
MEMBER_ID="${3:-M-10042}"

TABLE_NAME="${PROJECT_NAME}-unified-member-profile-${ENVIRONMENT}"

echo "============================================="
echo "  Member Data Verification"
echo "  Table: ${TABLE_NAME}"
echo "  Member: ${MEMBER_ID}"
echo "============================================="

echo ""
echo ">> Querying all records for ${MEMBER_ID}..."
echo ""

aws dynamodb query \
    --table-name "${TABLE_NAME}" \
    --key-condition-expression "memberId = :mid" \
    --expression-attribute-values "{\":mid\": {\"S\": \"${MEMBER_ID}\"}}" \
    --output json | jq -r '.Items[] | "\(.recordType.S)"'

echo ""
echo ">> Record counts by type:"
aws dynamodb query \
    --table-name "${TABLE_NAME}" \
    --key-condition-expression "memberId = :mid" \
    --expression-attribute-values "{\":mid\": {\"S\": \"${MEMBER_ID}\"}}" \
    --select COUNT \
    --output json | jq -r '.Count'

echo ""
echo ">> Checking for M-50001 (should NOT exist)..."
aws dynamodb query \
    --table-name "${TABLE_NAME}" \
    --key-condition-expression "memberId = :mid" \
    --expression-attribute-values "{\":mid\": {\"S\": \"M-50001\"}}" \
    --select COUNT \
    --output json | jq -r '"M-50001 records: " + (.Count | tostring)'

echo ""
echo "============================================="
echo "  Verification complete!"
echo "============================================="
