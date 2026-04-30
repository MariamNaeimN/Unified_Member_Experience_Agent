# =============================================================================
# IAM — Least-privilege roles for Lambda ETL
# =============================================================================

# --- Lambda Execution Role ---
resource "aws_iam_role" "lambda_etl_role" {
  name = "${var.project_name}-lambda-etl-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-etl-role"
    Role = "Lambda ETL Execution"
  }
}

# --- CloudWatch Logs (Lambda needs to write logs) ---
resource "aws_iam_role_policy" "lambda_logging" {
  name = "${var.project_name}-lambda-logging-${var.environment}"
  role = aws_iam_role.lambda_etl_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_etl.arn}:*"
      }
    ]
  })
}

# --- S3 Read/Write (read raw/, write processed/) ---
resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${var.project_name}-lambda-s3-access-${var.environment}"
  role = aws_iam_role.lambda_etl_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/raw/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:CopyObject"
        ]
        Resource = [
          "${aws_s3_bucket.data_lake.arn}/processed/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.data_lake.arn}/raw/*"
        ]
      }
    ]
  })
}

# --- DynamoDB Write (batch write processed records) ---
resource "aws_iam_role_policy" "lambda_dynamodb_access" {
  name = "${var.project_name}-lambda-dynamodb-access-${var.environment}"
  role = aws_iam_role.lambda_etl_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.unified_member_profile.arn,
          "${aws_dynamodb_table.unified_member_profile.arn}/index/*"
        ]
      }
    ]
  })
}

# =============================================================================
# IAM — Role for DynamoDB Stream Trigger Lambda
# =============================================================================

# --- Lambda Execution Role ---
resource "aws_iam_role" "lambda_trigger_role" {
  name = "${var.project_name}-lambda-trigger-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-trigger-role"
    Role = "Lambda Stream Trigger Execution"
  }
}

# --- CloudWatch Logs ---
resource "aws_iam_role_policy" "lambda_trigger_logging" {
  name = "${var.project_name}-lambda-trigger-logging-${var.environment}"
  role = aws_iam_role.lambda_trigger_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_trigger.arn}:*"
      }
    ]
  })
}

# --- DynamoDB Streams (read stream records) ---
resource "aws_iam_role_policy" "lambda_trigger_streams" {
  name = "${var.project_name}-lambda-trigger-streams-${var.environment}"
  role = aws_iam_role.lambda_trigger_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
        ]
        Resource = "${aws_dynamodb_table.unified_member_profile.arn}/stream/*"
      }
    ]
  })
}

# --- Step Functions StartExecution ---
resource "aws_iam_role_policy" "lambda_trigger_sfn" {
  name = "${var.project_name}-lambda-trigger-sfn-${var.environment}"
  role = aws_iam_role.lambda_trigger_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = local.step_function_arn
      }
    ]
  })
}

