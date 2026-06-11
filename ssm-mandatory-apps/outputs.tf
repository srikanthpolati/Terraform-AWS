###############################################################################
# Root Outputs
###############################################################################

output "s3_package_bucket" {
  description = "S3 bucket name for SSM Distributor packages"
  value       = aws_s3_bucket.ssm_packages.id
}

output "ec2_instance_profile_name" {
  description = "IAM instance profile name to attach to EC2 instances"
  value       = aws_iam_instance_profile.ec2_ssm.name
}

output "linux_state_manager_associations" {
  description = "State Manager association IDs for Linux"
  value       = module.ssm_linux.state_manager_association_ids
}

output "windows_state_manager_associations" {
  description = "State Manager association IDs for Windows"
  value       = module.ssm_windows.state_manager_association_ids
}

output "linux_distributor_documents" {
  description = "SSM Distributor document names for Linux packages"
  value       = module.ssm_linux.distributor_document_names
}

output "windows_distributor_documents" {
  description = "SSM Distributor document names for Windows packages"
  value       = module.ssm_windows.distributor_document_names
}

output "app_version_parameter_arns" {
  description = "SSM Parameter Store ARNs for mandatory app versions"
  value       = { for k, v in aws_ssm_parameter.app_versions : k => v.arn }
}
