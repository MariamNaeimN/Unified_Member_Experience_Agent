# =============================================================================
# Lambda: ws-disconnect — Cleans up connection record on WebSocket $disconnect
# Deletes CONNECTION#{connectionId} from DynamoDB
# =============================================================================

resource "aws_cloudwatch_log_group" "ws_disconnect" {
  name              = "/aws/lambda/${var.project_name}-ws-disconnect-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "ws_disconnect" {
  function_name = "${var.project_name}-ws-disconnect-${var.environment}"
  description   = "WebSocket $disconnect handler: removes connection record from DynamoDB"
  role          = aws_iam_role.ws_disconnect_role.arn
  handler       = "handler.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.ws_disconnect.output_path
  source_code_hash = data.archive_file.ws_disconnect.output_base64sha256

  environment {
    variables = {
      DYNAMODB_AGENT_TABLE_NAME = var.dynamodb_agent_table_name
    }
  }

  tags = {
    Name = "${var.project_name}-ws-disconnect"
    Role = "WebSocket Disconnect Handler"
  }

  depends_on = [aws_cloudwatch_log_group.ws_disconnect]
}

data "archive_file" "ws_disconnect" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda-ws-disconnect.zip"

  source {
    content  = <<-PYTHON
import json
import os
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_AGENT_TABLE_NAME"]


def lambda_handler(event, context):
    """
    $disconnect route handler.
    Deletes CONNECTION#{connectionId} record from DynamoDB.
    Returns statusCode 200 regardless of whether the record existed.
    """
    connection_id = event["requestContext"]["connectionId"]
    logger.info("Disconnect: connectionId=%s", connection_id)

    try:
        table = dynamodb.Table(TABLE_NAME)
        table.delete_item(
            Key={
                "memberId": f"CONNECTION#{connection_id}",
                "recordType": "META"
            }
        )
        logger.info("Connection record deleted: %s", connection_id)
    except Exception as e:
        # Log but don't fail — TTL will clean up stale records anyway
        logger.warning("Error deleting connection record %s: %s", connection_id, str(e))

    return {"statusCode": 200}
PYTHON
    filename = "handler.py"
  }
}
