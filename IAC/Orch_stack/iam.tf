# =============================================================================
# IAM — Roles for Lambda (Fetch + Analyze + Write-back + Workflows) and Step Functions
# =============================================================================

# Construct DynamoDB ARN from table name if ARN not provided
locals {
  dynamodb_arn = var.dynamodb_table_arn != "" ? var.dynamodb_table_arn : "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}"
}

# --- Lambda Execution Role ---
resource "aws_iam_role" "lambda_orch_role" {
  name = "${var.project_name}-lambda-orch-role-${var.environment}"

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
resource "aws_iam_role_policy" "lambda_orch_logging" {
  name = "${var.project_name}-lambda-orch-logging-${var.environment}"
  role = aws_iam_role.lambda_orch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
    }]
  })
}

# DynamoDB Read + Write
resource "aws_iam_role_policy" "lambda_orch_dynamodb" {
  name = "${var.project_name}-lambda-orch-dynamodb-${var.environment}"
  role = aws_iam_role.lambda_orch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:PutItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ]
      Resource = [
        local.dynamodb_arn,
        "${local.dynamodb_arn}/index/*",
        local.dynamodb_agent_table_arn,
        "${local.dynamodb_agent_table_arn}/index/*"
      ]
    }]
  })
}

# Bedrock InvokeModel + Streaming
resource "aws_iam_role_policy" "lambda_orch_bedrock" {
  name = "${var.project_name}-lambda-orch-bedrock-${var.environment}"
  role = aws_iam_role.lambda_orch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_model_id}"
    }]
  })
}

# SNS Publish
resource "aws_iam_role_policy" "lambda_orch_sns" {
  name = "${var.project_name}-lambda-orch-sns-${var.environment}"
  role = aws_iam_role.lambda_orch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["sns:Publish"]
      Resource = [
        aws_sns_topic.patient_notifications.arn,
        aws_sns_topic.care_team_alerts.arn,
        aws_sns_topic.pharmacy_alerts.arn
      ]
    }]
  })
}

# X-Ray Tracing
resource "aws_iam_role_policy" "lambda_orch_xray" {
  name = "${var.project_name}-lambda-orch-xray-${var.environment}"
  role = aws_iam_role.lambda_orch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets"
      ]
      Resource = "*"
    }]
  })
}

# --- Step Functions Execution Role ---
resource "aws_iam_role" "sfn_role" {
  name = "${var.project_name}-sfn-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

# Step Functions invoke Lambdas
resource "aws_iam_role_policy" "sfn_invoke_lambda" {
  name = "${var.project_name}-sfn-invoke-lambda-${var.environment}"
  role = aws_iam_role.sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        aws_lambda_function.fetch_profile.arn,
        aws_lambda_function.analyze_profile.arn,
        aws_lambda_function.write_results.arn,
        aws_lambda_function.execute_workflows.arn
      ]
    }]
  })
}

# Step Functions logging
resource "aws_iam_role_policy" "sfn_logging" {
  name = "${var.project_name}-sfn-logging-${var.environment}"
  role = aws_iam_role.sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups"
      ]
      Resource = "*"
    }]
  })
}

# Step Functions X-Ray
resource "aws_iam_role_policy" "sfn_xray" {
  name = "${var.project_name}-sfn-xray-${var.environment}"
  role = aws_iam_role.sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets"
      ]
      Resource = "*"
    }]
  })
}

# SES Send Email
resource "aws_iam_role_policy" "lambda_orch_ses" {
  name = "${var.project_name}-lambda-orch-ses-${var.environment}"
  role = aws_iam_role.lambda_orch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
    }]
  })
}

# Cognito ListUsers (to get care manager emails)
resource "aws_iam_role_policy" "lambda_orch_cognito" {
  name = "${var.project_name}-lambda-orch-cognito-${var.environment}"
  role = aws_iam_role.lambda_orch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cognito-idp:ListUsers"]
      Resource = "arn:aws:cognito-idp:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:userpool/${var.cognito_user_pool_id}"
    }]
  })
}
