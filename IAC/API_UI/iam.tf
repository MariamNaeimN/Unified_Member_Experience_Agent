# =============================================================================
# IAM — Lambda API role (Step Functions + DynamoDB + CloudWatch)
# =============================================================================

resource "aws_iam_role" "lambda_api_role" {
  name = "${var.project_name}-lambda-api-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# CloudWatch Logs
resource "aws_iam_role_policy" "lambda_api_logging" {
  name = "${var.project_name}-lambda-api-logging-${var.environment}"
  role = aws_iam_role.lambda_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
    }]
  })
}

# Step Functions — start and describe executions
resource "aws_iam_role_policy" "lambda_api_sfn" {
  name = "${var.project_name}-lambda-api-sfn-${var.environment}"
  role = aws_iam_role.lambda_api_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution", "states:DescribeExecution"]
      Resource = [
        local.step_function_arn,
        "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:execution:${var.project_name}-orchestration-${var.environment}:*"
      ]
    }]
  })
}

# DynamoDB — read for search and chat history
resource "aws_iam_role_policy" "lambda_api_dynamodb" {
  name = "${var.project_name}-lambda-api-dynamodb-${var.environment}"
  role = aws_iam_role.lambda_api_role.id

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
