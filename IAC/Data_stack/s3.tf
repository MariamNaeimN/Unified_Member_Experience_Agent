# =============================================================================
# S3 Data Lake — Raw data ingestion, processed archive, static UI assets
# Matches: project_Flow/MOCK-DATA.md → S3 Bucket Structure
# =============================================================================

resource "aws_s3_bucket" "data_lake" {
  bucket        = "${var.project_name}-data-lake-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name = "${var.project_name}-data-lake"
    Role = "Data Lake - Raw + Processed + Static"
  }
}

# --- Versioning (compliance: keep history of all data changes) ---
resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

# --- Encryption at rest (HIPAA requirement) ---
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- Block all public access (PHI protection) ---
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Lifecycle rules: move processed data to cheaper storage ---
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "archive-processed-data"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "raw-data-retention"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    transition {
      days          = 180
      storage_class = "STANDARD_IA"
    }
  }
}

# --- S3 Event Notification: trigger Lambda ETL on new file uploads ---
resource "aws_s3_bucket_notification" "data_lake_etl_trigger" {
  bucket = aws_s3_bucket.data_lake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/members/"
    filter_suffix       = ".csv"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/claims/"
    filter_suffix       = ".csv"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/pharmacy/"
    filter_suffix       = ".json"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/care-events/"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/providers/"
    filter_suffix       = ".csv"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.etl_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/conditions/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# --- Data source for account ID ---
data "aws_caller_identity" "current" {}
