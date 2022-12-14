#module "s3_buckets" {
#  source = "./sec_100_create_s3_bucket"
#}
#module "security_hub" {
#  source = "./100_enable_security_hub"
#}
#module "dependency_monitoring" {
#  source = "./operational-excellence/100_labs/100_dependency_monitoring"
#  notification_email = var.notification_email
#}
#module "automating_operations" {
#  source = "./operational-excellence/200_labs/200_automating_operations_with_playbooks_and_runbooks/"
#  cloud9_owner = var.cloud9_owner
#}
module "automated_deployment_of_detective_controls" {
  source = "./security/200_labs/200_automated_deployment_of_detective_controls/"
}