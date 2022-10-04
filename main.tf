#module "s3_buckets" {
#  source = "./sec_100_create_s3_bucket"
#}
#module "security_hub" {
#  source = "./100_enable_security_hub"
#}
module "dependency_monitoring" {
  source = "./operational-excellence/100_labs/100_dependency_monitoring"
}
