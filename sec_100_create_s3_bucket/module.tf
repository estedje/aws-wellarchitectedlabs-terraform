resource "aws_s3_bucket" "wellarchitectedlabs_bucket_1" {
  bucket = "wellarchitectedlabs-bucket-1"
}

resource "aws_s3_bucket_versioning" "wellarchitectedlabs_bucket_1_versioning" {
  bucket = aws_s3_bucket.wellarchitectedlabs_bucket_1.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_acl" "wellarchitectedlabs_bucket_1_acl" {
  bucket = aws_s3_bucket.wellarchitectedlabs_bucket_1.id
  acl    = "private"
}

###################################
# S3 Bucket Policy
###################################
resource "aws_s3_bucket_policy" "read_wellarchitectedlabs_bucket_1" {
  bucket = aws_s3_bucket.wellarchitectedlabs_bucket_1.id
  policy = data.aws_iam_policy_document.read_wellarchitectedlabs_bucket_1.json
}

resource "aws_s3_bucket_public_access_block" "wellarchitectedlabs_bucket_1_public_access_block" {
  bucket = aws_s3_bucket.wellarchitectedlabs_bucket_1.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.wellarchitectedlabs_bucket_1.id
  key    = "index.html"
  source = "${path.module}/resources/index.html"
}

locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_origin_access_control" "origin_access_control" {
  name                              = "wellarchitectedlabs_origin_access_control"
  description                       = "wellarchitectedlabs_origin_access_control Policy"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.wellarchitectedlabs_bucket_1.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.origin_access_control.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"



  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "read_wellarchitectedlabs_bucket_1" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.wellarchitectedlabs_bucket_1.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.wellarchitectedlabs_bucket_1.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}
