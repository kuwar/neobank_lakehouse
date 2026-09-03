resource "databricks_notification_destination" "email_shaurave" {
  display_name = "email_shaurave"
  config {
    email {
      addresses = ["kuwarsaurav21@gmail.com"]
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