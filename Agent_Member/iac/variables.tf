# =============================================================================
# Variables — Agent Member Tools API
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "member-experience"
}

variable "dynamodb_table_name" {
  description = "DynamoDB unified profile table name (source data)"
  type        = string
  default     = "member-experience-unified-profile-dev"
}

variable "dynamodb_agent_table_name" {
  description = "DynamoDB agent output table name"
  type        = string
  default     = "member-experience-agent-output-dev"
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
