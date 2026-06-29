# =============================================================================
# Provisioner Level: calls the splunk-forwarder root module
# This is the entry point your team uses per environment/account.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Adjust to your backend configuration
  # backend "s3" {
  #   bucket = "my-tf-state-bucket"
  #   key    = "splunk-forwarder/terraform.tfstate"
  #   region = "ap-southeast-2"
  # }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Call the root module
# Adjust `source` to your actual repo path or registry address.
# -----------------------------------------------------------------------------
module "splunk_forwarder" {
  source = "../"   # path to the root module (parent directory)

  # --- Identity ---------------------------------------------------------------
  name_prefix = var.name_prefix
  aws_region  = var.aws_region

  # --- S3 package location ----------------------------------------------------
  # The package lives in your internal S3 bucket — no internet download.
  # Example key structure: splunk/linux/<version>/<filename>.rpm or .deb
  s3_bucket = var.s3_bucket
  s3_key    = var.s3_key

  # --- Installation -----------------------------------------------------------
  splunk_install_dir = var.splunk_install_dir
  splunk_user        = var.splunk_user
  splunk_group       = var.splunk_group

  # --- Splunk config ----------------------------------------------------------
  deployment_server      = var.deployment_server
  deployment_server_port = var.deployment_server_port

  # Best practice: reference an SSM SecureString or Secrets Manager secret
  # rather than hardcoding here. Example using data source:
  #   splunk_admin_password = data.aws_ssm_parameter.splunk_pw.value
  splunk_admin_password = var.splunk_admin_password

  # --- Tags -------------------------------------------------------------------
  tags = merge(var.tags, {
    ManagedBy   = "terraform"
    Module      = "splunk-forwarder"
    Environment = var.name_prefix
  })
}

# -----------------------------------------------------------------------------
# Outputs surfaced at provisioner level
# -----------------------------------------------------------------------------
output "ssm_document_name" {
  description = "SSM document name — use this with send-command to install Splunk on a new instance."
  value       = module.splunk_forwarder.ssm_document_name
}

output "ssm_document_arn" {
  value = module.splunk_forwarder.ssm_document_arn
}

output "splunk_s3_policy_arn" {
  description = "Attach this IAM policy ARN to your EC2 instance role so instances can pull the package from S3."
  value       = module.splunk_forwarder.splunk_s3_policy_arn
}

output "manual_trigger_cli" {
  description = "Copy-paste CLI snippet to manually trigger Splunk install on a new EC2 instance."
  value       = module.splunk_forwarder.manual_trigger_cli
}
