###############################################################################
# Module: ssm-mandatory-apps-linux
#
# Creates all SSM resources needed to deploy and track mandatory applications
# on Linux EC2 instances:
#
#   - SSM Distributor package documents  (Splunk, Qualys, CarbonBlack)
#   - SSM Command document               (compliance check + install)
#   - SSM State Manager association      (CloudWatch Agent, tag-triggered)
#   - SSM State Manager association      (Inventory, scheduled, read-only)
#   - SSM Resource Data Sync             (Inventory → S3)
#
# The compliance/install document has NO schedule. It is triggered manually
# by an operator against specific new instances only — existing instances
# with agents already installed are never touched.
###############################################################################

###############################################################################
# SSM DISTRIBUTOR - Package Documents
# Define versioned packages stored in S3. SHA256 checksums must be updated
# after uploading the actual installer binaries to S3.
###############################################################################

resource "aws_ssm_document" "splunk_linux" {
  name            = "MandatoryApp-Splunk-Linux-${var.environment}"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.splunk_version
    publisher     = "Internal"
    description   = "Splunk Universal Forwarder for Linux - v${var.splunk_version}"
    packages = {
      linux = {
        "_any" = {
          "x86_64" = { file = "splunkforwarder-${var.splunk_version}-linux-x86_64.rpm" }
          "arm64"  = { file = "splunkforwarder-${var.splunk_version}-linux-aarch64.rpm" }
        }
      }
    }
    files = {
      "splunkforwarder-${var.splunk_version}-linux-x86_64.rpm" = {
        checksums = { sha256 = "REPLACE_WITH_ACTUAL_SHA256_X86_64" }
      }
      "splunkforwarder-${var.splunk_version}-linux-aarch64.rpm" = {
        checksums = { sha256 = "REPLACE_WITH_ACTUAL_SHA256_AARCH64" }
      }
    }
  })

  tags = merge(var.tags, {
    Application = "Splunk"
    OS          = "Linux"
    Version     = var.splunk_version
  })
}

resource "aws_ssm_document" "qualys_linux" {
  name            = "MandatoryApp-Qualys-Linux-${var.environment}"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.qualys_version
    publisher     = "Internal"
    description   = "Qualys Cloud Agent for Linux - v${var.qualys_version}"
    packages = {
      linux = {
        "_any" = {
          "x86_64" = { file = "qualys-cloud-agent-${var.qualys_version}-x86_64.rpm" }
          "arm64"  = { file = "qualys-cloud-agent-${var.qualys_version}-aarch64.rpm" }
        }
      }
    }
    files = {
      "qualys-cloud-agent-${var.qualys_version}-x86_64.rpm" = {
        checksums = { sha256 = "REPLACE_WITH_ACTUAL_SHA256_X86_64" }
      }
      "qualys-cloud-agent-${var.qualys_version}-aarch64.rpm" = {
        checksums = { sha256 = "REPLACE_WITH_ACTUAL_SHA256_AARCH64" }
      }
    }
  })

  tags = merge(var.tags, {
    Application = "Qualys"
    OS          = "Linux"
    Version     = var.qualys_version
  })
}

resource "aws_ssm_document" "carbonblack_linux" {
  name            = "MandatoryApp-CarbonBlack-Linux-${var.environment}"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.carbonblack_version
    publisher     = "Internal"
    description   = "CarbonBlack Agent for Linux - v${var.carbonblack_version}"
    packages = {
      linux = {
        "_any" = {
          "x86_64" = { file = "cb-psc-sensor-${var.carbonblack_version}-x86_64.rpm" }
          "arm64"  = { file = "cb-psc-sensor-${var.carbonblack_version}-aarch64.rpm" }
        }
      }
    }
    files = {
      "cb-psc-sensor-${var.carbonblack_version}-x86_64.rpm" = {
        checksums = { sha256 = "REPLACE_WITH_ACTUAL_SHA256_X86_64" }
      }
      "cb-psc-sensor-${var.carbonblack_version}-aarch64.rpm" = {
        checksums = { sha256 = "REPLACE_WITH_ACTUAL_SHA256_AARCH64" }
      }
    }
  })

  tags = merge(var.tags, {
    Application = "CarbonBlack"
    OS          = "Linux"
    Version     = var.carbonblack_version
  })
}

###############################################################################
# SSM COMMAND DOCUMENT - Compliance Check & Install (manual trigger only)
#
# Rendered from a YAML template. Each step calls a separate shell script
# stored alongside this module under scripts/. The document is referenced
# in outputs so operators can invoke it via Run Command or the runbook script.
###############################################################################

resource "aws_ssm_document" "compliance_install_linux" {
  name            = "MandatoryApp-ComplianceInstall-Linux-${var.environment}"
  document_type   = "Command"
  document_format = "YAML"

  content = templatefile("${path.module}/scripts/compliance_remediation.yaml.tpl", {
    environment              = var.environment
    s3_bucket                = var.s3_bucket_id
    splunk_version           = var.splunk_version
    qualys_version           = var.qualys_version
    cloudwatch_version       = var.cloudwatch_version
    carbonblack_version      = var.carbonblack_version
    splunk_deployment_server = var.splunk_deployment_server
    splunk_index_name        = var.splunk_index_name
    qualys_activation_id     = var.qualys_activation_id
    qualys_customer_id       = var.qualys_customer_id
    carbonblack_server_url   = var.carbonblack_server_url
    carbonblack_group_name   = var.carbonblack_group_name
    aws_region               = data.aws_region.current.name
  })

  tags = merge(var.tags, {
    Purpose = "MandatoryAppInstall"
    OS      = "Linux"
    RunMode = "ManualOnly"
  })
}

###############################################################################
# SSM STATE MANAGER - CloudWatch Agent (tag-triggered, no schedule)
#
# AWS-ConfigureAWSPackage is idempotent — it checks the installed version
# before acting. Tag a new instance with:
#   MandatoryApps-CloudWatch = pending
# to trigger this association. Remove or update the tag after confirmed install.
###############################################################################

resource "aws_ssm_association" "cloudwatch_linux" {
  name             = "AWS-ConfigureAWSPackage"
  association_name = "MandatoryApp-CloudWatch-Linux-${var.environment}"

  targets {
    key    = "tag:MandatoryApps-CloudWatch"
    values = ["pending"]
  }

  parameters = {
    action  = "Install"
    name    = "AmazonCloudWatchAgent"
    version = var.cloudwatch_version == "latest" ? "" : var.cloudwatch_version
  }

  # No schedule_expression — fires once when the association is applied to
  # a matching instance, never runs again unless manually re-triggered.
  apply_only_at_cron_interval = false
  compliance_severity         = "CRITICAL"

  output_location {
    s3_bucket_name = var.s3_bucket_id
    s3_key_prefix  = "ssm-output/linux/cloudwatch"
  }

  wait_for_success_timeout_seconds = 600
}

###############################################################################
# SSM STATE MANAGER - Inventory (scheduled, read-only)
#
# AWS-GatherSoftwareInventory only collects metadata — it never installs,
# modifies, or restarts anything. Safe to run on all Linux instances.
###############################################################################

resource "aws_ssm_association" "inventory_linux" {
  name             = "AWS-GatherSoftwareInventory"
  association_name = "MandatoryApp-Inventory-Linux-${var.environment}"

  targets {
    key    = "tag:OS"
    values = ["Linux"]
  }

  parameters = {
    applications                = "Enabled"
    awsComponents               = "Enabled"
    customInventory             = "Enabled"
    instanceDetailedInformation = "Enabled"
    networkConfig               = "Enabled"
    services                    = "Enabled"
  }

  schedule_expression = "rate(30 minutes)"
}

###############################################################################
# SSM RESOURCE DATA SYNC - Pushes inventory data to S3 for querying
###############################################################################

resource "aws_ssm_resource_data_sync" "inventory_linux" {
  name = "MandatoryApps-Inventory-Linux-${var.environment}"

  s3_destination {
    bucket_name = var.s3_bucket_id
    prefix      = "ssm-inventory/linux"
    region      = data.aws_region.current.name
    kms_key_arn = var.kms_key_arn
  }
}

###############################################################################
# SSM PARAMETER STORE - Target versions (source of truth)
# Scripts read from here at runtime so version changes don't need redeployment.
###############################################################################

resource "aws_ssm_parameter" "splunk_version" {
  name        = "/mandatory-apps/linux/splunk/target_version"
  type        = "String"
  value       = var.splunk_version
  description = "Target Splunk UF version for Linux compliance"
  tags        = var.tags
}

resource "aws_ssm_parameter" "qualys_version" {
  name        = "/mandatory-apps/linux/qualys/target_version"
  type        = "String"
  value       = var.qualys_version
  description = "Target Qualys Cloud Agent version for Linux compliance"
  tags        = var.tags
}

resource "aws_ssm_parameter" "cloudwatch_version" {
  name        = "/mandatory-apps/linux/cloudwatch/target_version"
  type        = "String"
  value       = var.cloudwatch_version
  description = "Target CloudWatch Agent version for Linux compliance"
  tags        = var.tags
}

resource "aws_ssm_parameter" "carbonblack_version" {
  name        = "/mandatory-apps/linux/carbonblack/target_version"
  type        = "String"
  value       = var.carbonblack_version
  description = "Target CarbonBlack Agent version for Linux compliance"
  tags        = var.tags
}

###############################################################################
# Data Sources
###############################################################################

data "aws_region" "current" {}
