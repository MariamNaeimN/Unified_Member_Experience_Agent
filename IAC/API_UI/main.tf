terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Stack       = "api-ui-layer"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  dynamodb_arn          = var.dynamodb_table_arn != "" ? var.dynamodb_table_arn : "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}"
  dynamodb_agent_arn    = var.dynamodb_agent_table_arn != "" ? var.dynamodb_agent_table_arn : "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_agent_table_name}"
  step_function_arn     = var.step_function_arn != "" ? var.step_function_arn : "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project_name}-orchestration-${var.environment}"
}
