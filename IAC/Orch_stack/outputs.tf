# =============================================================================
# Outputs
# =============================================================================

output "step_function_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.member_orchestration.arn
}

output "step_function_name" {
  description = "Step Functions state machine name"
  value       = aws_sfn_state_machine.member_orchestration.name
}

output "lambda_fetch_profile_arn" {
  description = "Fetch Profile Lambda ARN"
  value       = aws_lambda_function.fetch_profile.arn
}

output "lambda_analyze_profile_arn" {
  description = "Analyze Profile Lambda ARN"
  value       = aws_lambda_function.analyze_profile.arn
}

output "lambda_write_results_arn" {
  description = "Write Results Lambda ARN"
  value       = aws_lambda_function.write_results.arn
}

# --- Convenience: test command ---
output "test_command" {
  description = "Command to test the orchestration workflow"
  value       = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.member_orchestration.arn} --input '{\"memberId\":\"M-10042\"}'"
}

output "lambda_execute_workflows_arn" {
  description = "Execute Workflows Lambda ARN"
  value       = aws_lambda_function.execute_workflows.arn
}

output "sns_patient_topic_arn" {
  description = "SNS topic for patient SMS notifications"
  value       = aws_sns_topic.patient_notifications.arn
}

output "sns_care_team_topic_arn" {
  description = "SNS topic for care team email alerts"
  value       = aws_sns_topic.care_team_alerts.arn
}

output "sns_pharmacy_topic_arn" {
  description = "SNS topic for pharmacy alerts"
  value       = aws_sns_topic.pharmacy_alerts.arn
}
