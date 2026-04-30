# =============================================================================
# IAM — Agent Tools Lambda Role
# =============================================================================

resource "aws_iam_role" "agent_tools_role" {
  name = "${var.project_name}-agent-tools-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# --- CloudWatch Logs ---
resource "aws_iam_role_policy" "agent_tools_logging" {
  name = "${var.project_name}-agent-tools-logging-${var.environment}"
  role = aws_iam_role.agent_tools_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
    }]
  })
}

# --- DynamoDB Read Access (both tables + GSI indexes) ---
resource "aws_iam_role_policy" "agent_tools_dynamodb" {
  name = "${var.project_name}-agent-tools-dynamodb-${var.environment}"
  role = aws_iam_role.agent_tools_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      Resource = [
        local.dynamodb_arn,
        "${local.dynamodb_arn}/index/*",
        local.dynamodb_agent_arn,
        "${local.dynamodb_agent_arn}/index/*"
      ]
    }]
  })
}
