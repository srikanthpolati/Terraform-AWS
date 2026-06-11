###############################################################################
# Windows Module Outputs
###############################################################################

output "state_manager_association_ids" {
  description = "Map of State Manager association IDs for Windows"
  value = {
    splunk_uf    = aws_ssm_association.windows_install_splunk_uf.association_id
    qualys_agent = aws_ssm_association.windows_install_qualys_agent.association_id
    cloudwatch   = aws_ssm_association.windows_install_cloudwatch_agent.association_id
    carbonblack  = aws_ssm_association.windows_install_carbonblack.association_id
    compliance   = aws_ssm_association.windows_compliance_check.association_id
    inventory    = aws_ssm_association.windows_inventory.association_id
  }
}

output "distributor_document_names" {
  description = "SSM Distributor document names for Windows packages"
  value = {
    splunk_uf    = aws_ssm_document.windows_splunk_uf.name
    qualys_agent = aws_ssm_document.windows_qualys_agent.name
    cloudwatch   = aws_ssm_document.windows_cloudwatch_agent.name
    carbonblack  = aws_ssm_document.windows_carbonblack_agent.name
  }
}
