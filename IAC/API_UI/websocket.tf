# =============================================================================
# WebSocket API Gateway — Replaces REST API Gateway
# All client-server communication over a single persistent WebSocket connection
# Routes: $connect, $disconnect, sendMessage, getMembers, getMemberProfile,
#         getNotifications, updateNotification, getChatHistory
# =============================================================================

resource "aws_apigatewayv2_api" "websocket" {
  name                       = "${var.project_name}-websocket-${var.environment}"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"

  tags = {
    Name = "${var.project_name}-websocket"
    Role = "WebSocket API Gateway"
  }
}

# =============================================================================
# Stage — auto-deploy enabled
# =============================================================================

resource "aws_apigatewayv2_stage" "websocket" {
  api_id      = aws_apigatewayv2_api.websocket.id
  name        = var.environment
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  tags = {
    Name = "${var.project_name}-websocket-${var.environment}"
  }
}

# =============================================================================
# Integrations
# =============================================================================

resource "aws_apigatewayv2_integration" "ws_connect" {
  api_id             = aws_apigatewayv2_api.websocket.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_connect.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "ws_disconnect" {
  api_id             = aws_apigatewayv2_api.websocket.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_disconnect.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "ws_chat" {
  api_id             = aws_apigatewayv2_api.websocket.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_chat.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "ws_api" {
  api_id             = aws_apigatewayv2_api.websocket.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ws_api.invoke_arn
  integration_method = "POST"
}

# =============================================================================
# Routes
# =============================================================================

resource "aws_apigatewayv2_route" "ws_connect" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_connect.id}"
}

resource "aws_apigatewayv2_route" "ws_disconnect" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.ws_disconnect.id}"
}

resource "aws_apigatewayv2_route" "ws_send_message" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "sendMessage"
  target    = "integrations/${aws_apigatewayv2_integration.ws_chat.id}"
}

resource "aws_apigatewayv2_route" "ws_get_members" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "getMembers"
  target    = "integrations/${aws_apigatewayv2_integration.ws_api.id}"
}

resource "aws_apigatewayv2_route" "ws_get_member_profile" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "getMemberProfile"
  target    = "integrations/${aws_apigatewayv2_integration.ws_api.id}"
}

resource "aws_apigatewayv2_route" "ws_get_notifications" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "getNotifications"
  target    = "integrations/${aws_apigatewayv2_integration.ws_api.id}"
}

resource "aws_apigatewayv2_route" "ws_update_notification" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "updateNotification"
  target    = "integrations/${aws_apigatewayv2_integration.ws_api.id}"
}

resource "aws_apigatewayv2_route" "ws_get_chat_history" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "getChatHistory"
  target    = "integrations/${aws_apigatewayv2_integration.ws_api.id}"
}

# =============================================================================
# Lambda Permissions — Allow WebSocket API to invoke Lambdas
# =============================================================================

resource "aws_lambda_permission" "ws_connect" {
  statement_id  = "AllowWebSocketConnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_connect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket.execution_arn}/*/*"
}

resource "aws_lambda_permission" "ws_disconnect" {
  statement_id  = "AllowWebSocketDisconnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_disconnect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket.execution_arn}/*/*"
}

resource "aws_lambda_permission" "ws_chat" {
  statement_id  = "AllowWebSocketChat"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_chat.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket.execution_arn}/*/*"
}

resource "aws_lambda_permission" "ws_api" {
  statement_id  = "AllowWebSocketApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ws_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket.execution_arn}/*/*"
}
