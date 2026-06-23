###############################################################################
# Module Variables: ssm-mandatory-apps-linux
###############################################################################

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "s3_bucket_id" {
  description = "S3 bucket name for SSM Distributor package artifacts and Run Command output"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 server-side encryption (optional)"
  type        = string
  default     = null
}

# ----------------------------------------------------------------------------
# Application Versions
# These are written to SSM Parameter Store as the runtime source of truth.
# Scripts read from Parameter Store at execution time, so updating a version
# here (via terraform apply) takes effect on the next manual run.
# ----------------------------------------------------------------------------

variable "splunk_version" {
  description = "Target Splunk Universal Forwarder version for Linux"
  type        = string
}

variable "qualys_version" {
  description = "Target Qualys Cloud Agent version for Linux"
  type        = string
}

variable "cloudwatch_version" {
  description = "Target CloudWatch Agent version for Linux. Use 'latest' to let AWS manage it."
  type        = string
  default     = "latest"
}

variable "carbonblack_version" {
  description = "Target CarbonBlack Agent version for Linux"
  type        = string
}

# ----------------------------------------------------------------------------
# Application Configuration
# ----------------------------------------------------------------------------

variable "splunk_deployment_server" {
  description = "Splunk deployment server address (host:port)"
  type        = string
}

variable "splunk_index_name" {
  description = "Default Splunk index name"
  type        = string
  default     = "main"
}

variable "qualys_activation_id" {
  description = "Qualys Cloud Agent activation ID"
  type        = string
  sensitive   = true
}

variable "qualys_customer_id" {
  description = "Qualys Cloud Agent customer ID"
  type        = string
  sensitive   = true
}

variable "carbonblack_server_url" {
  description = "CarbonBlack server URL"
  type        = string
}

variable "carbonblack_group_name" {
  description = "CarbonBlack sensor group name"
  type        = string
  default     = "default"
}

# ----------------------------------------------------------------------------
# Tagging
# ----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources created by this module"
  type        = map(string)
  default     = {}
}
