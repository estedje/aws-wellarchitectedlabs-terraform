
data "aws_caller_identity" "current" {
}


data "aws_region" "current" {
}



variable "config" {
  description = "Configure AWS Config. If you have previously enabled Config select No."
  type        = bool
  default     = true
}


variable "guard_duty" {
  description = "Configure Amazon GuardDuty. If you have previously enabled GuardDuty select No."
  type        = bool
  default     = true
}


variable "security_hub" {
  description = "Configure AWS Security Hub. AWS Config must be enabled in this stack for Security Hub to work."
  type        = bool
  default     = true
}


variable "s3_bucket_policy_explicit_deny" {
  description = "Optional: Explicitly deny destructive actions to buckets created in this stack. Note: you will need to login as root to remove the bucket policy"
  type        = bool
  default     = false
}



variable "cloud_trail_bucket_name" {
  description = "The name of the new S3 bucket to create for CloudTrail to send logs to. Can contain only lower-case characters, numbers, periods, and dashes.Each label in the bucket name must start with a lowercase letter or number."
  type        = string
  default     = "wal-cloudtrail-logs"
}


variable "cloud_trail_cw_logs_retention_time" {
  description = "Number of days to retain logs in CloudWatch Logs. 0=Forever. Default 1 year, note logs are stored in S3 default 10 years"
  type        = number
  default     = 365
}


variable "cloud_trail_s3_retention_time" {
  description = "Number of days to retain logs in the S3 Bucket before they are automatically deleted. Default is ~ 10 years"
  type        = number
  default     = 3650
}


variable "cloud_trail_encrypt_s3_logs" {
  description = "OPTIONAL: Use KMS to enrypt logs stored in S3. A new key will be created"
  type        = bool
  default     = false
}


variable "cloud_trail_log_s3_data_events" {
  description = "OPTIONAL: These events provide insight into the resource operations performed on or within S3"
  type        = bool
  default     = false
}


variable "config_bucket_name" {
  description = "The name of the S3 bucket Config Service will store configuration snapshots in. Each label in the bucket name must start with a lowercase letter or number."
  type        = string
  default     = "wal-config-service-snapshot"
}


variable "config_snapshot_frequency" {
  description = "AWS Config configuration snapshot frequency"
  type        = string
  default     = "One_Hour"
}


variable "config_s3_retention_time" {
  description = "Number of days to retain logs in the S3 Bucket before they are automatically deleted. Default is ~ 10 years"
  type        = string
  default     = 3650
}


variable "guard_duty_email_address" {
  description = "Enter the email address that will receive the alerts"
  type        = string
  default     = "i0d6vkogs@mozmail.com"
}


resource "aws_kms_key" "cloud_trail_kms_key" {
  description = "KMS Key for Cloudtrail to use to encrypt logs stored in S3"
  policy = data.aws_iam_policy_document.cloud_trail_kms_key_policy.json
}

data "aws_iam_policy_document" "cloud_trail_kms_key_policy" {
  statement {
    sid       = "EnableIAMUserPermissions"
    actions    = ["kms:*"]
    effect    = "Allow"
    resources  = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "Allow CloudTrail to encrypt logs"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"]
    }
  }
  statement {
    sid       = "Allow CloudTrail to describe key"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
  statement {
    sid       = "Allow principals in the account to decrypt log files"
    actions   = ["kms:Decrypt","kms:ReEncryptFrom"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"]
    }
  }
  statement {
    sid       = "Allow alias creation during setup"
    actions   = ["kms:CreateAlias"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ec2.${data.aws_region.current.name}.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid       = "Enable cross account log decryption"
    actions   = ["kms:Decrypt","kms:ReEncryptFrom"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket" "cloud_trail_destination_bucket" {
  bucket = var.cloud_trail_bucket_name
}

resource "aws_s3_bucket_versioning" "cloud_trail_destination_bucket_versioning" {
  bucket = aws_s3_bucket.cloud_trail_destination_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_acl" "cloud_trail_destination_bucket_acl" {
  bucket = aws_s3_bucket.cloud_trail_destination_bucket.id
  acl    = "private"
}

###################################
# S3 Bucket Policy
###################################
resource "aws_s3_bucket_policy" "cloud_trail_bucket_policy" {
  bucket = aws_s3_bucket.cloud_trail_destination_bucket.id
  policy = data.aws_iam_policy_document.read_cloud_trail_destination_bucket.json
}


data "aws_iam_policy_document" "read_cloud_trail_destination_bucket" {
  statement {
    sid       = "AllowCloudTrailServiceGetAcl"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloud_trail_destination_bucket.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
  statement {
    sid       = "AllowCloudTrailOwnerPut"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloud_trail_destination_bucket.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
  statement {
    sid       = "AllowManagedAccountsCloudtrail"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloud_trail_destination_bucket.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["981588356137", "129689185312"]
    }
  }
}


resource "aws_s3_bucket_public_access_block" "cloud_trail_destination_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.cloud_trail_destination_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloud_trail_destination_bucket_lifecycle_configuration" {
  bucket = aws_s3_bucket.cloud_trail_destination_bucket.id

  rule {
    id     = "Delete"
    status = "Enabled"
    expiration {
      days = var.cloud_trail_s3_retention_time
    }
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.cloud_trail_destination_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}




resource "aws_cloudtrail" "cloud_trail_destination_trail" {
  name                       = "default"
  s3_bucket_name             = aws_s3_bucket.cloud_trail_destination_bucket.id
  cloud_watch_logs_group_arn =  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloud_trail_cw_logs_group.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloud_trail_cloud_watch_logs_role.arn
  enable_log_file_validation = true
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }
  include_global_service_events = true
  is_multi_region_trail         = true
  kms_key_id                    = aws_kms_key.cloud_trail_kms_key.arn
  depends_on = [
    aws_cloudwatch_log_group.cloud_trail_cw_logs_group]
}


resource "aws_cloudwatch_log_group" "cloud_trail_cw_logs_group" {
  retention_in_days = var.cloud_trail_cw_logs_retention_time
}


resource "aws_iam_role" "cloud_trail_cloud_watch_logs_role" {
  assume_role_policy = data.aws_iam_policy_document.cloudtrail-assume-role-policy.json
  inline_policy {
    name = "CloudtrailInteractionPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["logs:CreateLogStream"]
          Effect   = "Allow"
          Resource = aws_cloudwatch_log_group.cloud_trail_cw_logs_group.arn
        },
        {
          Action   = ["logs:PutLogEvents"]
          Effect   = "Allow"
          Resource = aws_cloudwatch_log_group.cloud_trail_cw_logs_group.arn
        },
      ]
    })
  }
}
data "aws_iam_policy_document" "cloudtrail-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "config_role" {
  assume_role_policy  = data.aws_iam_policy_document.config-assume-role-policy.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"]
  path                = "/service-role/"
  inline_policy {
    name = "ConfigServiceS3"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["s3:PutObject"]
          Effect   = "Allow"
          Resource = aws_cloudwatch_log_group.cloud_trail_cw_logs_group.arn
        },
        {
          Action   = ["s3:GetBucketAcl"]
          Effect   = "Allow"
          Resource = aws_cloudwatch_log_group.cloud_trail_cw_logs_group.arn
        },
      ]
    })
  }
}

data "aws_iam_policy_document" "config-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_config_delivery_channel" "config_delivery_channel" {
  name = "default"
  snapshot_delivery_properties  {
    delivery_frequency = var.config_snapshot_frequency
  }
  s3_bucket_name = aws_s3_bucket.config_bucket.id
  depends_on     = [aws_config_configuration_recorder.config_recorder]
}


resource "aws_config_configuration_recorder" "config_recorder" {
  name = "default"
  recording_group {
    all_supported               = true
    include_global_resource_types  = true
  }
  role_arn = aws_iam_role.config_role.arn
}


resource "aws_s3_bucket" "config_bucket" {
  bucket = var.config_bucket_name
}

resource "aws_s3_bucket_public_access_block" "config_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.config_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "config_bucket_lifecycle_configuration" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    id     = "Delete"
    status = "Enabled"
    expiration {
      days = var.config_s3_retention_time
    }
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket_server_side_encryption_configuration" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_versioning" "config_bucket_bucket_versioning" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_acl" "config_bucket_bucket_acl" {
  bucket = aws_s3_bucket.config_bucket.id
  acl    = "private"
}

###################################
# S3 Bucket Policy
###################################
resource "aws_s3_bucket_policy" "config_bucket_policy" {
  bucket = aws_s3_bucket.config_bucket.id
  policy = data.aws_iam_policy_document.read_config_bucket.json
}


data "aws_iam_policy_document" "read_config_bucket" {
  statement {
    sid       = "CloudtrailConfigServiceACLCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config_bucket.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
  statement {
    sid       = "CloudtrailConfigServiceWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config_bucket.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
  statement {
    sid       = "ConfigServiceACLCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config_bucket.arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
  statement {
    sid       = "ConfigServiceWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config_bucket.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

}


resource "aws_guardduty_detector" "guard_duty_detector" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}


resource "aws_sns_topic" "guard_duty_sns_topic" {
  name = "GuardDuty-Email"
}



resource "aws_cloudwatch_event_rule" "guard_duty_cw_event" {
  description   = "GuardDuty Email Event"
  event_pattern = <<EOF
{
  "detail-type": ["GuardDuty Finding"],
  "source": ["GuardDuty Finding"]
}
EOF
}
resource "aws_cloudwatch_event_target" "guard_duty_cw_event_sns" {
  rule      = aws_cloudwatch_event_rule.guard_duty_cw_event.name
  target_id = "GuardDuty-Email"
  arn       = aws_sns_topic.guard_duty_sns_topic.id
}

resource "aws_sns_topic_subscription" "sns-guard_duty_sns_subscription" {
  topic_arn = aws_sns_topic.guard_duty_sns_topic.arn
  protocol  = "email"
  endpoint  = var.guard_duty_email_address
}


resource "aws_securityhub_account" "security_hub_single_acc" {
}


output "cloud_trail_bucket_name" {
  description = "S3 bucket for CloudTrail logs"
  value       = aws_s3_bucket.cloud_trail_destination_bucket.id
}


