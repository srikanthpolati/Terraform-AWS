# =============================================================================
# Root Module Variables: splunk-forwarder
# =============================================================================

variable "name_prefix" {
  description = "Prefix applied to all resource names for namespacing."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region where resources are deployed."
  type        = string
}

# --- S3 Package Source -------------------------------------------------------

variable "s3_bucket" {
  description = "Name of the S3 bucket that contains the Splunk UF installer package."
  type        = string
}

variable "s3_key" {
  description = "S3 object key (full path) to the Splunk UF package, e.g. splunk/linux/splunkforwarder-9.x.x-linux-2.6-x86_64.rpm"
  type        = string
}

# --- Installation Settings ---------------------------------------------------

variable "splunk_install_dir" {
  description = "Base filesystem directory for the Splunk installation."
  type        = string
  default     = "/opt"
}

variable "splunk_user" {
  description = "OS user account under which Splunk runs."
  type        = string
  default     = "splunk"
}

variable "splunk_group" {
  description = "OS group for the Splunk user account."
  type        = string
  default     = "splunk"
}

# --- Splunk Configuration ----------------------------------------------------

variable "deployment_server" {
  description = "Hostname or IP of the Splunk Deployment Server (DS)."
  type        = string
}

variable "deployment_server_port" {
  description = "Port of the Splunk Deployment Server (default 8089)."
  type        = number
  default     = 8089
}

variable "splunk_admin_password" {
  description = "Seed password for the Splunk admin user. Use SSM Parameter Store or Secrets Manager in production."
  type        = string
  sensitive   = true
}

# --- Tagging -----------------------------------------------------------------

variable "tags" {
  description = "Map of tags applied to all created resources."
  type        = map(string)
  default     = {}
}
