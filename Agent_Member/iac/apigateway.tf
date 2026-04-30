# =============================================================================
# REST API Gateway — Agent Tools API
# Exposes MCP tools as HTTP endpoints for external clients
# =============================================================================

resource "aws_api_gateway_rest_api" "agent_tools" {
  name        = "${var.project_name}-agent-tools-api-${var.environment}"
  description = "REST API exposing MCP agent tools over HTTP"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.project_name}-agent-tools-api"
    Role = "MCP Tools REST API"
  }
}

# ── /tools resource ─────────────────────────────────────────────────────────

resource "aws_api_gateway_resource" "tools" {
  rest_api_id = aws_api_gateway_rest_api.agent_tools.id
  parent_id   = aws_api_gateway_rest_api.agent_tools.root_resource_id
  path_part   = "tools"
}

# GET /tools — list all available tools
resource "aws_api_gateway_method" "tools_get" {
  rest_api_id   = aws_api_gateway_rest_api.agent_tools.id
  resource_id   = aws_api_gateway_resource.tools.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "tools_get" {
  rest_api_id             = aws_api_gateway_rest_api.agent_tools.id
  resource_id             = aws_api_gateway_resource.tools.id
  http_method             = aws_api_gateway_method.tools_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.agent_tools.invoke_arn
}

# OPTIONS /tools — CORS preflight
resource "aws_api_gateway_method" "tools_options" {
  rest_api_id   = aws_api_gateway_rest_api.agent_tools.id
  resource_id   = aws_api_gateway_resource.tools.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "tools_options" {
  rest_api_id = aws_api_gateway_rest_api.agent_tools.id
  resource_id = aws_api_gateway_resource.tools.id
  http_method = aws_api_gateway_method.tools_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "tools_options_200" {
  rest_api_id = aws_api_gateway_rest_api.agent_tools.id
  resource_id = aws_api_gateway_resource.tools.id
  http_method = aws_api_gateway_method.tools_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "tools_options_200" {
  rest_api_id = aws_api_gateway_rest_api.agent_tools.id
  resource_id = aws_api_gateway_resource.tools.id
  http_method = aws_api_gateway_method.tools_options.http_method
  status_code = aws_api_gateway_method_response.tools_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# ── /tools/{toolName} resource ──────────────────────────────────────────────

resource "aws_api_gateway_resource" "tool_name" {
  rest_api_id = aws_api_gateway_rest_api.agent_tools.id
  parent_id   = aws_api_gateway_resource.tools.id
  path_part   = "{toolName}"
}

# POST /tools/{toolName} — invoke a specific tool
resource "aws_api_gateway_method" "tool_post" {
  rest_api_id   = aws_api_gateway_rest_api.agent_tools.id
  resource_id   = aws_api_gateway_resource.tool_name.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "tool_post" {
  rest_api_id             = aws_api_gateway_rest_api.agent_tools.id
  resource_id             = aws_api_gateway_resource.tool_name.id
  http_method             = aws_api_gateway_method.tool_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.agent_tools.invoke_arn
}

# GET /tools/{toolName} — for tools that don't need a body (e.g. get_all_members_summary)
resource "aws_api_gateway_method" "tool_get" {
  rest_api_id   = aws_api_gateway_rest_api.agent_tools.id
  resource_id   = aws_api_gateway_resource.tool_name.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "tool_get" {
  rest_api_id             = aws_api_gateway_rest_api.agent_tools.id
  resource_id             = aws_api_gateway_resource.tool_name.id
  http_method             = aws_api_gateway_method.tool_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.agent_tools.invoke_arn
}

# OPTIONS /tools/{toolName} — CORS preflight
resource "aws_api_gateway_method" "tool_options" {
  rest_api_id   = aws_api_gateway_rest_api.agent_tools.id
  resource_id   = aws_api_gateway_resource.tool_name.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "tool_options" {
  rest_api_id = aws_api_gateway_rest_api.agent_tools.id
  resource_id = aws_api_gateway_resource.tool_name.id
  http_method = aws_api_gateway_method.tool_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "tool_options_200" {
  rest_api_id = aws_api_gateway_rest_api.agent_tools.id
  resource_id = aws_api_gateway_resource.tool_name.id
  http_method = aws_api_gateway_method.tool_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "tool_options_200" {
  rest_api_id = aws_api_gateway_rest_api.agent_tools.id
  resource_id = aws_api_gateway_resource.tool_name.id
  http_method = aws_api_gateway_method.tool_options.http_method
  status_code = aws_api_gateway_method_response.tool_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# ── Deployment & Stage ──────────────────────────────────────────────────────

resource "aws_api_gateway_deployment" "agent_tools" {
  rest_api_id = aws_api_gateway_rest_api.agent_tools.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.tools.id,
      aws_api_gateway_resource.tool_name.id,
      aws_api_gateway_method.tools_get.id,
      aws_api_gateway_method.tool_post.id,
      aws_api_gateway_method.tool_get.id,
      aws_api_gateway_integration.tools_get.id,
      aws_api_gateway_integration.tool_post.id,
      aws_api_gateway_integration.tool_get.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.tools_get,
    aws_api_gateway_integration.tool_post,
    aws_api_gateway_integration.tool_get,
    aws_api_gateway_integration.tools_options,
    aws_api_gateway_integration.tool_options,
  ]
}

resource "aws_api_gateway_stage" "agent_tools" {
  deployment_id = aws_api_gateway_deployment.agent_tools.id
  rest_api_id   = aws_api_gateway_rest_api.agent_tools.id
  stage_name    = var.environment

  tags = {
    Name = "${var.project_name}-agent-tools-${var.environment}"
  }
}

# ── Lambda permissions for API Gateway ──────────────────────────────────────

resource "aws_lambda_permission" "agent_tools_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.agent_tools.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.agent_tools.execution_arn}/*/*"
}
