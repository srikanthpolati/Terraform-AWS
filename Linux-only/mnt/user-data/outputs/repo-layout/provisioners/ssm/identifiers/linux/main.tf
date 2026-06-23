###############################################################################
# Provisioner: ssm / Identifier: linux
#
# Entry point for deploying the Linux mandatory application SSM playbook.
# Calls the reusable module and wires in environment-specific values.
#
# To install mandatory apps on a new instance, use the runbook:
#   ./run_mandatory_apps.sh --instance-id i-0abc123 --os linux
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }

  # Update this block to match your backend configuration
  # backend "s3" {
  #   bucket = "my-terraform-state"
  #   key    = "ssm/linux/terraform.tfstate"
  #   region = "ap-southeast-2"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Provisioner = "ssm"
      Identifier  = "linux"
      Environment = var.environment
    }
  }
}

###############################################################################
# S3 Bucket for package artifacts and Run Command output logs
# If you already have a bucket, remove this resource and pass the name directly
# into the module via s3_bucket_id below.
###############################################################################

resource "aws_s3_bucket" "ssm_packages" {
  bucket = var.s3_bucket_name

  tags = {
    Name    = var.s3_bucket_name
    Purpose = "SSM-MandatoryApps-Packages"
  }
}

resource "aws_s3_bucket_versioning" "ssm_packages" {
  bucket = aws_s3_bucket.ssm_packages.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_packages" {
  bucket = aws_s3_bucket.ssm_packages.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
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
# IAM Role and Instance Profile
# Attach the instance profile to every EC2 instance that needs to be managed.
###############################################################################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_ec2" {
  name               = "SSMMandatoryApps-Linux-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "EC2 role for SSM mandatory app management - Linux"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ssm_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "ssm_s3_access" {
  statement {
    sid    = "ReadSSMPackages"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.ssm_packages.arn,
      "${aws_s3_bucket.ssm_packages.arn}/*"
    ]
  }

  statement {
    sid    = "SSMComplianceAndInventory"
    effect = "Allow"
    actions = [
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid     = "KMSDecrypt"
      effect  = "Allow"
      actions = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "ssm_s3_access" {
  name   = "SSMMandatoryApps-Linux-S3Access-${var.environment}"
  policy = data.aws_iam_policy_document.ssm_s3_access.json
}

resource "aws_iam_role_policy_attachment" "ssm_s3_access" {
  role       = aws_iam_role.ssm_ec2.name
  policy_arn = aws_iam_policy.ssm_s3_access.arn
}

resource "aws_iam_instance_profile" "ssm_ec2" {
  name = "SSMMandatoryApps-Linux-${var.environment}"
  role = aws_iam_role.ssm_ec2.name
}

###############################################################################
# Module Call
###############################################################################

module "ssm_mandatory_apps_linux" {
  source = "../../../../modules/ssm-mandatory-apps-linux"

  environment = var.environment
  s3_bucket_id = aws_s3_bucket.ssm_packages.id
  kms_key_arn  = var.kms_key_arn

  # Application versions — update here to change compliance targets
  splunk_version      = var.splunk_version
  qualys_version      = var.qualys_version
  cloudwatch_version  = var.cloudwatch_version
  carbonblack_version = var.carbonblack_version

  # Splunk configuration
  splunk_deployment_server = var.splunk_deployment_server
  splunk_index_name        = var.splunk_index_name

  # Qualys configuration
  qualys_activation_id = var.qualys_activation_id
  qualys_customer_id   = var.qualys_customer_id

  # CarbonBlack configuration
  carbonblack_server_url = var.carbonblack_server_url
  carbonblack_group_name = var.carbonblack_group_name

  tags = {
    Provisioner = "ssm"
    Identifier  = "linux"
    Environment = var.environment
  }
}
