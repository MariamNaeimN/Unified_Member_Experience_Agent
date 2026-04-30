# =============================================================================
# Outputs
# =============================================================================

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.care_managers.id
}

output "cognito_client_id" {
  description = "Cognito App Client ID (for UI login)"
  value       = aws_cognito_user_pool_client.chat_ui.id
}

output "cognito_region" {
  description = "Cognito region"
  value       = var.aws_region
}

# --- WebSocket API ---
output "websocket_url" {
  description = "WebSocket API endpoint URL"
  value       = "${aws_apigatewayv2_stage.websocket.invoke_url}"
}

output "websocket_connect_command" {
  description = "Command to test WebSocket connection (replace TOKEN)"
  value       = "wscat -c '${aws_apigatewayv2_stage.websocket.invoke_url}?token=TOKEN'"
}

# --- Test commands ---
output "signup_command" {
  description = "Command to sign up a test user"
  value       = "aws cognito-idp sign-up --client-id ${aws_cognito_user_pool_client.chat_ui.id} --username sarah@example.com --password TestPass123 --user-attributes Name=name,Value=Sarah Name=email,Value=sarah@example.com"
}

output "confirm_command" {
  description = "Command to confirm user (admin)"
  value       = "aws cognito-idp admin-confirm-sign-up --user-pool-id ${aws_cognito_user_pool.care_managers.id} --username sarah@example.com"
}

output "login_command" {
  description = "Command to get auth token"
  value       = "aws cognito-idp initiate-auth --client-id ${aws_cognito_user_pool_client.chat_ui.id} --auth-flow USER_PASSWORD_AUTH --auth-parameters USERNAME=sarah@example.com,PASSWORD=TestPass123"
}
