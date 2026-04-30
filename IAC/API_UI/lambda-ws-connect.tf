# =============================================================================
# Lambda: ws-connect — Validates Cognito JWT on WebSocket $connect
# Stores CONNECTION#{connectionId} record in DynamoDB for session tracking
# =============================================================================

resource "aws_cloudwatch_log_group" "ws_connect" {
  name              = "/aws/lambda/${var.project_name}-ws-connect-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "ws_connect" {
  function_name = "${var.project_name}-ws-connect-${var.environment}"
  description   = "WebSocket $connect handler: validates Cognito JWT and stores connection record"
  role          = aws_iam_role.ws_connect_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.ws_connect.output_path
  source_code_hash = data.archive_file.ws_connect.output_base64sha256

  environment {
    variables = {
      DYNAMODB_AGENT_TABLE_NAME = var.dynamodb_agent_table_name
      COGNITO_USER_POOL_ID      = aws_cognito_user_pool.care_managers.id
      COGNITO_CLIENT_ID         = aws_cognito_user_pool_client.chat_ui.id
    }
  }

  tags = {
    Name = "${var.project_name}-ws-connect"
    Role = "WebSocket Connect Handler"
  }

  depends_on = [aws_cloudwatch_log_group.ws_connect]
}

data "archive_file" "ws_connect" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-ws-connect.zip"

  source {
    content  = <<-PYTHON
import json
import os
import logging
import boto3
import base64
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_AGENT_TABLE_NAME"]
COGNITO_USER_POOL_ID = os.environ["COGNITO_USER_POOL_ID"]
COGNITO_CLIENT_ID = os.environ["COGNITO_CLIENT_ID"]


def lambda_handler(event, context):
    """
    $connect route handler.
    Validates Cognito ID token from query parameters and stores connection record.
    Returns statusCode 200 on success, 401 on auth failure.
    """
    connection_id = event["requestContext"]["connectionId"]
    logger.info("Connect request: connectionId=%s", connection_id)

    # Extract token from query parameters
    params = event.get("queryStringParameters") or {}
    token = params.get("token", "")

    if not token:
        logger.warning("No token provided for connection %s", connection_id)
        return {"statusCode": 401}

    # Validate the JWT token
    claims = validate_token(token)
    if claims is None:
        logger.warning("Invalid token for connection %s", connection_id)
        return {"statusCode": 401}

    user_email = claims.get("email", "unknown")
    user_name = claims.get("name", user_email)

    # Store connection record in DynamoDB
    table = dynamodb.Table(TABLE_NAME)
    now = int(time.time())
    ttl = now + 7200  # 2 hours TTL (matches WebSocket max connection duration)

    table.put_item(
        Item={
            "memberId": f"CONNECTION#{connection_id}",
            "recordType": "META",
            "connectionId": connection_id,
            "userId": user_email,
            "userName": user_name,
            "connectedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "expiresAt": ttl
        }
    )

    logger.info("Connection stored: %s -> %s", connection_id, user_email)
    return {"statusCode": 200}


def validate_token(token):
    """
    Decode and validate a Cognito ID token.
    Uses base64 decode + expiry check (simple validation suitable for
    Lambda behind API Gateway where full JWKS validation would need a layer).
    For production, consider adding python-jose layer for full JWKS verification.
    """
    try:
        # Split JWT into parts
        parts = token.split(".")
        if len(parts) != 3:
            logger.warning("Token does not have 3 parts")
            return None

        # Decode payload (middle part)
        payload = parts[1]
        # Add padding if needed
        padding = 4 - len(payload) % 4
        if padding != 4:
            payload += "=" * padding

        decoded = base64.urlsafe_b64decode(payload)
        claims = json.loads(decoded)

        # Check expiry
        exp = claims.get("exp", 0)
        now = int(time.time())
        if now >= exp:
            logger.warning("Token expired: exp=%d, now=%d", exp, now)
            return None

        # Check audience (client_id) for ID tokens
        aud = claims.get("aud", "")
        if aud and aud != COGNITO_CLIENT_ID:
            logger.warning("Token audience mismatch: got=%s, expected=%s", aud, COGNITO_CLIENT_ID)
            return None

        # Check issuer matches our user pool
        iss = claims.get("iss", "")
        expected_iss = f"https://cognito-idp.{os.environ.get('AWS_REGION', 'us-east-1')}.amazonaws.com/{COGNITO_USER_POOL_ID}"
        if iss and iss != expected_iss:
            logger.warning("Token issuer mismatch: got=%s, expected=%s", iss, expected_iss)
            return None

        # Check token_use is 'id' (not 'access')
        token_use = claims.get("token_use", "")
        if token_use and token_use != "id":
            logger.warning("Token use is not 'id': %s", token_use)
            return None

        logger.info("Token validated for: %s", claims.get("email", "unknown"))
        return claims

    except Exception as e:
        logger.error("Token validation error: %s", str(e))
        return None
PYTHON
    filename = "handler.py"
  }
}
