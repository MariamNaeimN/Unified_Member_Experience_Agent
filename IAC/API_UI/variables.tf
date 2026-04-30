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

variable "step_function_arn" {
  description = "Step Functions state machine ARN from Orch Stack (optional - auto-constructed if empty)"
  type        = string
  default     = ""
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name from Data Stack"
  type        = string
  default     = "member-experience-unified-profile-dev"
}

variable "dynamodb_table_arn" {
  description = "DynamoDB table ARN from Data Stack (optional - auto-constructed if empty)"
  type        = string
  default     = ""
}

variable "dynamodb_agent_table_name" {
  description = "DynamoDB agent output table name from Data Stack"
  type        = string
  default     = "member-experience-agent-output-dev"
}

variable "dynamodb_agent_table_arn" {
  description = "DynamoDB agent output table ARN from Data Stack (optional)"
  type        = string
  default     = ""
}

variable "lambda_runtime" {
  type    = string
  default = "python3.12"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "bedrock_model_id" {
  description = "Bedrock model ID for AI chat analysis"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}
