# =============================================================================
# Cognito — User sign-up / login for care managers
# Sarah signs up once, then logs in with email + password
# JWT token is used to authenticate API Gateway requests
# =============================================================================

resource "aws_cognito_user_pool" "care_managers" {
  name = "${var.project_name}-care-managers-${var.environment}"

  # Sign-up settings
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  # User attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 5
      max_length = 256
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  schema {
    name                = "custom:role"
    attribute_data_type = "String"
    required            = false
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 50
    }
  }

  # Email verification
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Member Experience Agent - Verify Your Email"
    email_message        = "Your verification code is {####}"
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = {
    Name = "${var.project_name}-care-managers"
    Role = "User Authentication"
  }
}

# --- App Client (for the chat UI) ---
resource "aws_cognito_user_pool_client" "chat_ui" {
  name         = "${var.project_name}-chat-ui-${var.environment}"
  user_pool_id = aws_cognito_user_pool.care_managers.id

  # Auth flows
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  # Token validity
  access_token_validity  = 1   # 1 hour
  id_token_validity      = 1   # 1 hour
  refresh_token_validity = 30  # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # No client secret (public client for SPA)
  generate_secret = false

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"
}
