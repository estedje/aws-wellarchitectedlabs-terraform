resource "aws_s3_bucket" "wellarchitectedlabs_bucket_1" {
  bucket = "wellarchitectedlabs-bucket-1"
  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_acl" "wellarchitectedlabs_bucket_1_acl" {
  bucket = aws_s3_bucket.wellarchitectedlabs-bucket-1.id
  acl    = "private"
}

resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.wellarchitectedlabs_bucket_1.id
  key    = "index"
  source = "./resources/index.html"
}
