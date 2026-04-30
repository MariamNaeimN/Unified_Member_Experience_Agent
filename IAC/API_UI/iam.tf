# =============================================================================
# IAM — Lambda Roles
# =============================================================================

# --- REST API Lambda Role — REMOVED ---
# The lambda_api_role and its policies (lambda_api_logging, lambda_api_sfn,
# lambda_api_dynamodb) have been removed. The REST API Lambda no longer exists.
# WebSocket Lambda roles are defined below.

# =============================================================================
# WebSocket Lambda Roles
# =============================================================================

# --- ws-connect Lambda Role ---
resource "aws_iam_role" "ws_connect_role" {
  name = "${var.project_name}-ws-connect-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ws_connect_logging" {
  name = "${var.project_name}-ws-connect-logging-${var.environment}"
  role = aws_iam_role.ws_connect_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
    }]
  })
}

resource "aws_iam_role_policy" "ws_connect_dynamodb" {
  name = "${var.project_name}-ws-connect-dynamodb-${var.environment}"
  role = aws_iam_role.ws_connect_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem"]
      Resource = [local.dynamodb_agent_arn]
    }]
  })
}

# --- ws-disconnect Lambda Role ---
resource "aws_iam_role" "ws_disconnect_role" {
  name = "${var.project_name}-ws-disconnect-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ws_disconnect_logging" {
  name = "${var.project_name}-ws-disconnect-logging-${var.environment}"
  role = aws_iam_role.ws_disconnect_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
    }]
  })
}

resource "aws_iam_role_policy" "ws_disconnect_dynamodb" {
  name = "${var.project_name}-ws-disconnect-dynamodb-${var.environment}"
  role = aws_iam_role.ws_disconnect_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:DeleteItem"]
      Resource = [local.dynamodb_agent_arn]
    }]
  })
}

# --- ws-chat Lambda Role ---
resource "aws_iam_role" "ws_chat_role" {
  name = "${var.project_name}-ws-chat-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ws_chat_logging" {
  name = "${var.project_name}-ws-chat-logging-${var.environment}"
  role = aws_iam_role.ws_chat_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
    }]
  })
}

resource "aws_iam_role_policy" "ws_chat_dynamodb" {
  name = "${var.project_name}-ws-chat-dynamodb-${var.environment}"
  role = aws_iam_role.ws_chat_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:PutItem", "dynamodb:UpdateItem"]
      Resource = [
        local.dynamodb_arn,
        "${local.dynamodb_arn}/index/*",
        local.dynamodb_agent_arn,
        "${local.dynamodb_agent_arn}/index/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "ws_chat_bedrock" {
  name = "${var.project_name}-ws-chat-bedrock-${var.environment}"
  role = aws_iam_role.ws_chat_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModelWithResponseStream"]
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_model_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:InvokeAgentRuntime"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ws_chat_apigw_management" {
  name = "${var.project_name}-ws-chat-apigw-mgmt-${var.environment}"
  role = aws_iam_role.ws_chat_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["execute-api:ManageConnections"]
      Resource = "${aws_apigatewayv2_api.websocket.execution_arn}/${var.environment}/POST/@connections/*"
    }]
  })
}

# --- ws-api Lambda Role ---
resource "aws_iam_role" "ws_api_role" {
  name = "${var.project_name}-ws-api-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ws_api_logging" {
  name = "${var.project_name}-ws-api-logging-${var.environment}"
  role = aws_iam_role.ws_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
    }]
  })
}

resource "aws_iam_role_policy" "ws_api_dynamodb" {
  name = "${var.project_name}-ws-api-dynamodb-${var.environment}"
  role = aws_iam_role.ws_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:UpdateItem"]
      Resource = [
        local.dynamodb_arn,
        "${local.dynamodb_arn}/index/*",
        local.dynamodb_agent_arn,
        "${local.dynamodb_agent_arn}/index/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "ws_api_apigw_management" {
  name = "${var.project_name}-ws-api-apigw-mgmt-${var.environment}"
  role = aws_iam_role.ws_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["execute-api:ManageConnections"]
      Resource = "${aws_apigatewayv2_api.websocket.execution_arn}/${var.environment}/POST/@connections/*"
    }]
  })
}
