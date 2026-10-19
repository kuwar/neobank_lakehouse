# One set of destinations for all envs. The bundle looks them up by display name
# (databricks.yaml: slack_destination_id, email_destination_id), so don't rename.
resource "databricks_notification_destination" "neobank_email_notification" {
  display_name = "neobank_email_notification"
  config {
    email {
      addresses = var.email_notification_addresses
    }
  }
}

resource "databricks_notification_destination" "slack_neobank" {
  display_name = "slack_neobank"
  config {
    slack {
      url = var.slack_webhook_url
    }
  }
}
