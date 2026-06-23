###############################################################################
# Provisioner Variables: ssm / linux
###############################################################################

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be one of: dev, staging, prod."
  }
}

variable "s3_bucket_name" {
  description = "S3 bucket name for SSM package artifacts and Run Command output logs"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for S3 encryption (optional)"
  type        = string
  default     = null
}

# ----------------------------------------------------------------------------
# Application Versions
# ----------------------------------------------------------------------------

variable "splunk_version" {
  description = "Target Splunk Universal Forwarder version"
  type        = string
}

variable "qualys_version" {
  description = "Target Qualys Cloud Agent version"
  type        = string
}

variable "cloudwatch_version" {
  description = "Target CloudWatch Agent version ('latest' lets AWS manage it)"
  type        = string
  default     = "latest"
}

variable "carbonblack_version" {
  description = "Target CarbonBlack Agent version"
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
