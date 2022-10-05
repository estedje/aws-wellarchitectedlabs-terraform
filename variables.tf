variable "notification_email" {
  description = "The email address to which CloudWatch Alarm notifications are published."
  type        = string
}
variable "cloud9_owner" {
  description = "Arn of the owner of cloud9-env"
  type        = string
}
