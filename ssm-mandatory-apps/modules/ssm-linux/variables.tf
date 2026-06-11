###############################################################################
# Linux Module Variables
###############################################################################

variable "environment" {
  type = string
}

variable "s3_bucket_id" {
  type = string
}

variable "s3_bucket_arn" {
  type = string
}

variable "linux_target_key" {
  type = string
}

variable "linux_target_values" {
  type = list(string)
}

variable "mandatory_app_versions" {
  type = map(string)
}

variable "schedule_expression" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "splunk_deployment_server" {
  type = string
}

variable "qualys_activation_id" {
  type      = string
  sensitive = true
}

variable "qualys_customer_id" {
  type      = string
  sensitive = true
}

variable "carbonblack_server_url" {
  type = string
}

variable "carbonblack_group_name" {
  type = string
}
