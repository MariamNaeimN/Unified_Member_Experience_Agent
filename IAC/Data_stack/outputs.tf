# =============================================================================
# Outputs — Values needed by other stacks and for mock data upload
# =============================================================================

output "s3_data_lake_bucket_name" {
  description = "S3 data lake bucket name"
  value       = aws_s3_bucket.data_lake.id
}

output "s3_data_lake_bucket_arn" {
  description = "S3 data lake bucket ARN"
  value       = aws_s3_bucket.data_lake.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB unified member profile table name"
  value       = aws_dynamodb_table.unified_member_profile.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB unified member profile table ARN"
  value       = aws_dynamodb_table.unified_member_profile.arn
}

output "dynamodb_agent_table_name" {
  description = "DynamoDB agent output table name"
  value       = aws_dynamodb_table.agent_output.name
}

output "dynamodb_agent_table_arn" {
  description = "DynamoDB agent output table ARN"
  value       = aws_dynamodb_table.agent_output.arn
}

output "lambda_etl_function_name" {
  description = "Lambda ETL processor function name"
  value       = aws_lambda_function.etl_processor.function_name
}

output "lambda_etl_function_arn" {
  description = "Lambda ETL processor function ARN"
  value       = aws_lambda_function.etl_processor.arn
}

output "lambda_etl_role_arn" {
  description = "Lambda ETL IAM role ARN"
  value       = aws_iam_role.lambda_etl_role.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for Lambda ETL"
  value       = aws_cloudwatch_log_group.lambda_etl.name
}

# --- Convenience: upload command ---
output "mock_data_upload_command" {
  description = "Command to upload mock data to S3"
  value       = "aws s3 sync ./mock-data/ s3://${aws_s3_bucket.data_lake.id}/raw/ --region ${var.aws_region}"
}
