#module "s3_buckets" {
#  source = "./sec_100_create_s3_bucket"
#}
module "security_hub" {
  source = "./100_enable_security_hub"
}

