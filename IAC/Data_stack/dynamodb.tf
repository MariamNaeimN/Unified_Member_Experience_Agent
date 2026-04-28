# =============================================================================
# DynamoDB — Unified Member Profile (Single-Table Design)
# Matches: project_Flow/MOCK-DATA.md → DynamoDB Table Design
#
# PK: memberId (e.g., "M-10042")
# SK: recordType#recordId (e.g., "CLAIM#CLM-50001", "PHARMACY#RX-70001")
#
# Single query on memberId returns ALL data for a member:
#   Member, Patient, Conditions, Claims, Pharmacy, Care Events,
#   Providers, Care Gaps, AI Decisions, Interventions, Summaries
# =============================================================================

resource "aws_dynamodb_table" "unified_member_profile" {
  name         = "${var.project_name}-unified-profile-${var.environment}"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "memberId"
  range_key    = "recordType"

  # --- Primary Key ---
  attribute {
    name = "memberId"
    type = "S"
  }

  attribute {
    name = "recordType"
    type = "S"
  }

  # --- GSI: Query by record type across all members ---
  # e.g., "show all open CARE_GAP records" or "all overdue PHARMACY records"
  attribute {
    name = "gsiRecordType"
    type = "S"
  }

  global_secondary_index {
    name            = "recordType-index"
    hash_key        = "gsiRecordType"
    range_key       = "memberId"
    projection_type = "ALL"
  }

  # --- Encryption at rest (HIPAA) ---
  server_side_encryption {
    enabled = true
  }

  # --- Point-in-time recovery (compliance) ---
  point_in_time_recovery {
    enabled = true
  }

  # --- TTL for auto-expiring summaries ---
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-unified-profile"
    Role = "Unified Member Profile Store + Audit Trail"
  }
}
