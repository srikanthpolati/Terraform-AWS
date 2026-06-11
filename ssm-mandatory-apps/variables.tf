###############################################################################
# Root Variables
###############################################################################

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

# ── Target Selection ──────────────────────────────────────────────────────────
# SSM targets instances using tag key/value pairs. The modules use these
# to scope State Manager associations and Inventory collection.

variable "linux_target_key" {
  description = "Tag key used to identify Linux EC2 instances"
  type        = string
  default     = "tag:OS"
}

variable "linux_target_values" {
  description = "Tag values matching Linux instances"
  type        = list(string)
  default     = ["Linux", "Amazon Linux", "RHEL", "Ubuntu"]
}

variable "windows_target_key" {
  description = "Tag key used to identify Windows EC2 instances"
  type        = string
  default     = "tag:OS"
}

variable "windows_target_values" {
  description = "Tag values matching Windows instances"
  type        = list(string)
  default     = ["Windows"]
}

# ── Mandatory App Version Targets ────────────────────────────────────────────
# These versions are stored in SSM Parameter Store and referenced by
# installation scripts and compliance checks. Update here to change
# the target version across the entire estate.

variable "mandatory_app_versions" {
  description = "Target versions for each mandatory application"
  type        = map(string)
  default = {
    splunk_uf     = "9.3.0"
    qualys_agent  = "4.7.0"
    cloudwatch    = "3.3.0"
    carbonblack   = "3.9.1"
  }
}

# ── Schedule ─────────────────────────────────────────────────────────────────

variable "schedule_expression" {
  description = "Cron/rate expression for State Manager association schedule"
  type        = string
  default     = "rate(1 day)"
  # Examples:
  # "rate(1 day)"         - run daily
  # "rate(12 hours)"      - run every 12 hours
  # "cron(0 2 * * ? *)"   - run at 2am UTC daily
}

# ── Application Configuration ─────────────────────────────────────────────────
# Agent-specific configuration passed into installation scripts

variable "splunk_deployment_server" {
  description = "Splunk Deployment Server URI (host:port)"
  type        = string
  # e.g. "splunk-ds.internal.example.com:8089"
}

variable "qualys_activation_id" {
  description = "Qualys Cloud Agent Activation ID"
  type        = string
  sensitive   = true
}

variable "qualys_customer_id" {
  description = "Qualys Cloud Agent Customer ID"
  type        = string
  sensitive   = true
}

variable "carbonblack_server_url" {
  description = "CarbonBlack CBC server URL"
  type        = string
  # e.g. "https://defense.conferdeploy.net"
}

variable "carbonblack_group_name" {
  description = "CarbonBlack sensor group/policy name for these instances"
  type        = string
}
