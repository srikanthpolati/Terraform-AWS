###############################################################################
# Module Outputs: ssm-mandatory-apps-linux
###############################################################################

output "run_command_document_name" {
  description = "Name of the SSM Command document to invoke manually on new Linux instances"
  value       = aws_ssm_document.compliance_install_linux.name
}

output "inventory_association_id" {
  description = "SSM State Manager association ID for Inventory (runs on schedule, read-only)"
  value       = aws_ssm_association.inventory_linux.association_id
}

output "cloudwatch_association_id" {
  description = "SSM State Manager association ID for CloudWatch Agent (tag-triggered)"
  value       = aws_ssm_association.cloudwatch_linux.association_id
}

output "distributor_package_names" {
  description = "SSM Distributor package document names"
  value = {
    splunk      = aws_ssm_document.splunk_linux.name
    qualys      = aws_ssm_document.qualys_linux.name
    carbonblack = aws_ssm_document.carbonblack_linux.name
  }
}

output "parameter_store_paths" {
  description = "SSM Parameter Store paths where target versions are stored"
  value = {
    splunk      = aws_ssm_parameter.splunk_version.name
    qualys      = aws_ssm_parameter.qualys_version.name
    cloudwatch  = aws_ssm_parameter.cloudwatch_version.name
    carbonblack = aws_ssm_parameter.carbonblack_version.name
  }
}
