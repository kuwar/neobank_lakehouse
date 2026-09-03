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