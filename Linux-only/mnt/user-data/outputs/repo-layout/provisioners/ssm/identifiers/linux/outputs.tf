###############################################################################
# Provisioner Outputs: ssm / linux
###############################################################################

output "instance_profile_name" {
  description = "IAM instance profile name — attach this to all managed Linux EC2 instances"
  value       = aws_iam_instance_profile.ssm_ec2.name
}

output "run_command_document_name" {
  description = "SSM document to invoke manually on new Linux instances to install mandatory apps"
  value       = module.ssm_mandatory_apps_linux.run_command_document_name
}

output "s3_bucket_name" {
  description = "S3 bucket holding package artifacts and Run Command output logs"
  value       = aws_s3_bucket.ssm_packages.id
}

output "distributor_packages" {
  description = "SSM Distributor package document names"
  value       = module.ssm_mandatory_apps_linux.distributor_package_names
}

output "parameter_store_version_paths" {
  description = "SSM Parameter Store paths holding the target versions for each app"
  value       = module.ssm_mandatory_apps_linux.parameter_store_paths
}

output "compliance_console_url" {
  description = "AWS Console URL — SSM Compliance dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/systems-manager/compliance"
}

output "inventory_console_url" {
  description = "AWS Console URL — SSM Inventory dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/systems-manager/inventory"
}
