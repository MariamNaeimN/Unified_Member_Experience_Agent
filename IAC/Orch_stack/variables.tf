variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "member-experience"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name from Data Stack"
  type        = string
  default     = "member-experience-unified-profile-dev"
}

variable "dynamodb_table_arn" {
  description = "DynamoDB table ARN from Data Stack (optional - will be constructed from table name if empty)"
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

variable "bedrock_model_id" {
  description = "Bedrock model ID for AI analysis"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 120
}

variable "lambda_memory" {
  description = "Lambda memory in MB"
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
