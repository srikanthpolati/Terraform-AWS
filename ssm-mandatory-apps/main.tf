###############################################################################
# SSM Mandatory Application Management - Root Configuration
# Manages: Splunk UF, Qualys Agent, CloudWatch Agent, CarbonBlack Agent
# Components: Distributor, State Manager, Inventory, Compliance
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

###############################################################################
# S3 Bucket - Stores installation packages for SSM Distributor
###############################################################################

resource "aws_s3_bucket" "ssm_packages" {
  bucket = "${var.environment}-ssm-mandatory-app-packages-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.common_tags, {
    Name    = "${var.environment}-ssm-mandatory-packages"
    Purpose = "SSM Distributor package storage"
  })
}

resource "aws_s3_bucket_versioning" "ssm_packages" {
  bucket = aws_s3_bucket.ssm_packages.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_packages" {
  bucket = aws_s3_bucket.ssm_packages.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ssm_packages" {
  bucket                  = aws_s3_bucket.ssm_packages.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###############################################################################
# IAM Role for EC2 instances (SSM access + S3 package access)
###############################################################################

resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.environment}-ec2-ssm-mandatory-apps-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "ssm_s3_packages" {
  name = "${var.environment}-ssm-s3-packages-access"
  role = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMPackageS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ssm_packages.arn,
          "${aws_s3_bucket.ssm_packages.arn}/*"
        ]
      },
      {
        Sid    = "SSMDistributorAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.environment}-ec2-ssm-mandatory-apps-profile"
  role = aws_iam_role.ec2_ssm_role.name
  tags = var.common_tags
}

###############################################################################
# SSM Parameters - Version configuration (single source of truth)
# Update these to control which versions are considered compliant
###############################################################################

resource "aws_ssm_parameter" "app_versions" {
  for_each = var.mandatory_app_versions

  name  = "/mandatory-apps/versions/${each.key}"
  type  = "String"
  value = each.value

  tags = merge(var.common_tags, {
    Purpose = "Mandatory app target version - drives compliance evaluation"
  })
}

###############################################################################
# Invoke Linux Module
###############################################################################

module "ssm_linux" {
  source = "./modules/ssm-linux"

  environment         = var.environment
  s3_bucket_id        = aws_s3_bucket.ssm_packages.id
  s3_bucket_arn       = aws_s3_bucket.ssm_packages.arn
  linux_target_key    = var.linux_target_key
  linux_target_values = var.linux_target_values
  mandatory_app_versions = var.mandatory_app_versions
  schedule_expression = var.schedule_expression
  common_tags         = var.common_tags
  splunk_deployment_server = var.splunk_deployment_server
  qualys_activation_id     = var.qualys_activation_id
  qualys_customer_id       = var.qualys_customer_id
  carbonblack_server_url   = var.carbonblack_server_url
  carbonblack_group_name   = var.carbonblack_group_name
}

###############################################################################
# Invoke Windows Module
###############################################################################

module "ssm_windows" {
  source = "./modules/ssm-windows"

  environment           = var.environment
  s3_bucket_id          = aws_s3_bucket.ssm_packages.id
  s3_bucket_arn         = aws_s3_bucket.ssm_packages.arn
  windows_target_key    = var.windows_target_key
  windows_target_values = var.windows_target_values
  mandatory_app_versions = var.mandatory_app_versions
  schedule_expression   = var.schedule_expression
  common_tags           = var.common_tags
  splunk_deployment_server = var.splunk_deployment_server
  qualys_activation_id     = var.qualys_activation_id
  qualys_customer_id       = var.qualys_customer_id
  carbonblack_server_url   = var.carbonblack_server_url
  carbonblack_group_name   = var.carbonblack_group_name
}

###############################################################################
# Data sources
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
