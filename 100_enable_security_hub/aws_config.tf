#--------------
# S3 Variable
#--------------
variable "encryption_enabled" {
  type        = bool
  default     = true
  description = "When set to 'true' the resource will have AES256 encryption enabled by default"
}

# Get current region of Terraform stack
data "aws_region" "current" {}

# Get current account number
data "aws_caller_identity" "current" {}

# Retrieves the partition that it resides in
data "aws_partition" "current" {}

# -----------------------------------------------------------
# set up the AWS IAM Role to assign to AWS Config Service
# -----------------------------------------------------------
resource "aws_iam_role" "config_role" {
  name = "awsconfig-example"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "config.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "config_policy_attach" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSConfigRole"
}

resource "aws_iam_role_policy_attachment" "read_only_policy_attach" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

# -----------------------------------------------------------
# set up the AWS Config Recorder
# -----------------------------------------------------------
resource "aws_config_configuration_recorder" "config_recorder" {

  name     = "config_recorder"
  role_arn = aws_iam_role.config_role.arn
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

# -----------------------------------------------------------
# Create AWS S3 bucket for AWS Config to record configuration history and snapshots
# -----------------------------------------------------------
resource "aws_s3_bucket" "new_config_bucket" {
  bucket        = "config-bucket-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "new_config_bucket_acl" {
  bucket = aws_s3_bucket.new_config_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "new_config_bucket_server_side_encryption_configuration" {
  bucket = aws_s3_bucket.new_config_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "new_config_bucket_1_public_access_block" {
  bucket                  = aws_s3_bucket.new_config_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------
# Define AWS S3 bucket policies
# -----------------------------------------------------------
resource "aws_s3_bucket_policy" "config_logging_policy" {
  bucket = aws_s3_bucket.new_config_bucket.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBucketAcl",
      "Effect": "Allow",
      "Principal": {
        "Service": [
         "config.amazonaws.com"
        ]
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "${aws_s3_bucket.new_config_bucket.arn}",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "true"
        }
      }
    },
    {
      "Sid": "AllowConfigWriteAccess",
      "Effect": "Allow",
      "Principal": {
        "Service": [
         "config.amazonaws.com"
        ]
      },
      "Action": "s3:PutObject",
      "Resource": "${aws_s3_bucket.new_config_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        },
        "Bool": {
          "aws:SecureTransport": "true"
        }
      }
    },
    {
      "Sid": "RequireSSL",
      "Effect": "Deny",
      "Principal": {
        "AWS": "*"
      },
      "Action": "s3:*",
      "Resource": "${aws_s3_bucket.new_config_bucket.arn}/*",
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
POLICY
}

# -----------------------------------------------------------
# Set up Delivery channel resource and bucket location to specify configuration history location.
# -----------------------------------------------------------
resource "aws_config_delivery_channel" "config_channel" {
  s3_bucket_name = aws_s3_bucket.new_config_bucket.id
  depends_on     = [aws_config_configuration_recorder.config_recorder]
}

# -----------------------------------------------------------
# Enable AWS Config Recorder
# -----------------------------------------------------------
resource "aws_config_configuration_recorder_status" "config_recorder_status" {
  name       = aws_config_configuration_recorder.config_recorder.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.config_channel]
}

# -----------------------------------------------------------
# set up the Conformance Pack
# -----------------------------------------------------------
resource "aws_config_conformance_pack" "s3conformancepack" {
  name = "s3conformancepack"

  template_body = <<EOT

Resources:
  S3BucketPublicReadProhibited:
    Type: AWS::Config::ConfigRule
    Properties:
      ConfigRuleName: S3BucketPublicReadProhibited
      Description: >- 
        Checks that your Amazon S3 buckets do not allow public read access.
        The rule checks the Block Public Access settings, the bucket policy, and the
        bucket access control list (ACL).
      Scope:
        ComplianceResourceTypes:
        - "AWS::S3::Bucket"
      Source:
        Owner: AWS
        SourceIdentifier: S3_BUCKET_PUBLIC_READ_PROHIBITED
      MaximumExecutionFrequency: Six_Hours
  S3BucketPublicWriteProhibited: 
    Type: "AWS::Config::ConfigRule"
    Properties: 
      ConfigRuleName: S3BucketPublicWriteProhibited
      Description: "Checks that your Amazon S3 buckets do not allow public write access. The rule checks the Block Public Access settings, the bucket policy, and the bucket access control list (ACL)."
      Scope: 
        ComplianceResourceTypes: 
        - "AWS::S3::Bucket"
      Source: 
        Owner: AWS
        SourceIdentifier: S3_BUCKET_PUBLIC_WRITE_PROHIBITED
      MaximumExecutionFrequency: Six_Hours
  S3BucketReplicationEnabled: 
    Type: "AWS::Config::ConfigRule"
    Properties: 
      ConfigRuleName: S3BucketReplicationEnabled
      Description: "Checks whether the Amazon S3 buckets have cross-region replication enabled."
      Scope: 
        ComplianceResourceTypes: 
        - "AWS::S3::Bucket"
      Source: 
        Owner: AWS
        SourceIdentifier: S3_BUCKET_REPLICATION_ENABLED
  S3BucketSSLRequestsOnly: 
    Type: "AWS::Config::ConfigRule"
    Properties: 
      ConfigRuleName: S3BucketSSLRequestsOnly
      Description: "Checks whether S3 buckets have policies that require requests to use Secure Socket Layer (SSL)."
      Scope: 
        ComplianceResourceTypes: 
        - "AWS::S3::Bucket"
      Source: 
        Owner: AWS
        SourceIdentifier: S3_BUCKET_SSL_REQUESTS_ONLY
  ServerSideEncryptionEnabled: 
    Type: "AWS::Config::ConfigRule"
    Properties: 
      ConfigRuleName: ServerSideEncryptionEnabled
      Description: "Checks that your Amazon S3 bucket either has S3 default encryption enabled or that the S3 bucket policy explicitly denies put-object requests without server side encryption."
      Scope: 
        ComplianceResourceTypes: 
        - "AWS::S3::Bucket"
      Source: 
        Owner: AWS
        SourceIdentifier: S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED
  S3BucketLoggingEnabled: 
    Type: "AWS::Config::ConfigRule"
    Properties: 
      ConfigRuleName: S3BucketLoggingEnabled
      Description: "Checks whether logging is enabled for your S3 buckets."
      Scope: 
        ComplianceResourceTypes: 
        - "AWS::S3::Bucket"
      Source: 
        Owner: AWS
        SourceIdentifier: S3_BUCKET_LOGGING_ENABLED

EOT

  depends_on = [aws_config_configuration_recorder.config_recorder]
}
