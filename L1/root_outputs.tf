# =============================================================================
# Root Module Outputs: splunk-forwarder
# =============================================================================

output "ssm_document_name" {
  description = "Name of the SSM document to use with aws ssm send-command."
  value       = aws_ssm_document.splunk_forwarder_install.name
}

output "ssm_document_arn" {
  description = "ARN of the SSM document."
  value       = aws_ssm_document.splunk_forwarder_install.arn
}

output "splunk_s3_policy_arn" {
  description = "ARN of the IAM policy that grants EC2 instances S3 read access for the Splunk package. Attach this to your EC2 instance role."
  value       = aws_iam_policy.splunk_s3_read.arn
}

output "ssm_parameter_doc_name" {
  description = "SSM Parameter Store path where the SSM document name is stored for cross-stack reference."
  value       = aws_ssm_parameter.splunk_ssm_doc_name.name
}

output "manual_trigger_cli" {
  description = "Example AWS CLI command to manually trigger the Splunk install on a new instance."
  value       = <<-EOT
    aws ssm send-command \
      --document-name "${aws_ssm_document.splunk_forwarder_install.name}" \
      --targets "Key=instanceids,Values=<NEW_INSTANCE_ID>" \
      --region <AWS_REGION> \
      --comment "Manual Splunk UF install on new instance" \
      --output text
  EOT
}
