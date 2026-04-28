# =============================================================================
# SNS — Notification topics for workflow triggers
# Routes: SMS to patient, Email alerts to care team, Pharmacy alerts
# =============================================================================

# --- Patient notifications (SMS) ---
resource "aws_sns_topic" "patient_notifications" {
  name = "${var.project_name}-patient-notifications-${var.environment}"

  tags = {
    Name = "${var.project_name}-patient-notifications"
    Role = "SMS notifications to patients"
  }
}

# --- Care team alerts (Email) ---
resource "aws_sns_topic" "care_team_alerts" {
  name = "${var.project_name}-care-team-alerts-${var.environment}"

  tags = {
    Name = "${var.project_name}-care-team-alerts"
    Role = "Email alerts to care managers and coordinators"
  }
}

# --- Pharmacy alerts ---
resource "aws_sns_topic" "pharmacy_alerts" {
  name = "${var.project_name}-pharmacy-alerts-${var.environment}"

  tags = {
    Name = "${var.project_name}-pharmacy-alerts"
    Role = "Alerts to pharmacy teams"
  }
}

# --- Subscribe a demo email to care team alerts (optional) ---
# Uncomment and set your email to receive demo alerts:
# resource "aws_sns_topic_subscription" "care_team_email" {
#   topic_arn = aws_sns_topic.care_team_alerts.arn
#   protocol  = "email"
#   endpoint  = "your-email@example.com"
# }
