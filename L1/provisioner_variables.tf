# =============================================================================
# Provisioner Level Variables
# =============================================================================

variable "name_prefix" {
  description = "Environment/account prefix, e.g. prod, staging, dev."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-southeast-2"
}

# --- S3 Package -------------------------------------------------------------

variable "s3_bucket" {
  description = "S3 bucket holding the Splunk UF installer (no internet access needed)."
  type        = string
  # example: "my-software-packages-bucket"
}

variable "s3_key" {
  description = "Full S3 object key to the Splunk installer package."
  type        = string
  # example: "splunk/linux/9.2.1/splunkforwarder-9.2.1-linux-2.6-x86_64.rpm"
}

# --- Install Settings -------------------------------------------------------

variable "splunk_install_dir" {
  type    = string
  default = "/opt"
}

variable "splunk_user" {
  type    = string
  default = "splunk"
}

variable "splunk_group" {
  type    = string
  default = "splunk"
}

# --- Splunk Config ----------------------------------------------------------

variable "deployment_server" {
  description = "Splunk Deployment Server hostname or IP."
  type        = string
}

variable "deployment_server_port" {
  type    = number
  default = 8089
}

variable "splunk_admin_password" {
  description = "Splunk admin seed password. Prefer referencing SSM Parameter Store."
  type        = string
  sensitive   = true
}

# --- Tags -------------------------------------------------------------------

variable "tags" {
  type    = map(string)
  default = {}
}
