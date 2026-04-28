# =============================================================================
# DynamoDB — Agent Output Table (separate from source data)
# Stores: Chat History, AI Decisions, Care Gaps, Interventions, Summaries
#
# PK: memberId (e.g., "M-10042")
# SK: recordType#recordId (e.g., "CHAT_HISTORY#CH-123", "AI_DECISION#D-456")
# =============================================================================

resource "aws_dynamodb_table" "agent_output" {
  name         = "${var.project_name}-agent-output-${var.environment}"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "memberId"
  range_key    = "recordType"

  attribute {
    name = "memberId"
    type = "S"
  }

  attribute {
    name = "recordType"
    type = "S"
  }

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

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-agent-output"
    Role = "Agent Output Store"
  }
}
