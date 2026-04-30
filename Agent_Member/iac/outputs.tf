# =============================================================================
# Outputs — Agent Tools API
# =============================================================================

output "api_url" {
  description = "Agent Tools API base URL"
  value       = aws_api_gateway_stage.agent_tools.invoke_url
}

output "lambda_function_name" {
  description = "Agent Tools Lambda function name"
  value       = aws_lambda_function.agent_tools.function_name
}

output "test_list_tools" {
  description = "curl: List all available tools"
  value       = "curl -s ${aws_api_gateway_stage.agent_tools.invoke_url}/tools | jq"
}

output "test_search_member" {
  description = "curl: Search for a member by name"
  value       = "curl -s -X POST ${aws_api_gateway_stage.agent_tools.invoke_url}/tools/search_member -H 'Content-Type: application/json' -d '{\"query\": \"John Smith\"}' | jq"
}

output "test_get_member_analysis" {
  description = "curl: Get AI analysis for a member"
  value       = "curl -s -X POST ${aws_api_gateway_stage.agent_tools.invoke_url}/tools/get_member_analysis -H 'Content-Type: application/json' -d '{\"memberId\": \"M-10042\"}' | jq"
}

output "test_get_all_members" {
  description = "curl: Get all members summary"
  value       = "curl -s ${aws_api_gateway_stage.agent_tools.invoke_url}/tools/get_all_members_summary | jq"
}

output "test_get_high_risk" {
  description = "curl: Get high-risk members"
  value       = "curl -s -X POST ${aws_api_gateway_stage.agent_tools.invoke_url}/tools/get_high_risk_members -H 'Content-Type: application/json' -d '{\"min_risk_score\": 80}' | jq"
}

output "test_get_member_profile" {
  description = "curl: Get full member profile"
  value       = "curl -s -X POST ${aws_api_gateway_stage.agent_tools.invoke_url}/tools/get_member_profile -H 'Content-Type: application/json' -d '{\"memberId\": \"M-10042\"}' | jq"
}

output "test_get_member_medications" {
  description = "curl: Get member medications"
  value       = "curl -s -X POST ${aws_api_gateway_stage.agent_tools.invoke_url}/tools/get_member_medications -H 'Content-Type: application/json' -d '{\"memberId\": \"M-10042\"}' | jq"
}
