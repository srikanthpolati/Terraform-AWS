# =============================================================================
# Root Module: splunk-forwarder
# Defines all resource blocks for the Splunk UF SSM installation document.
# Called by provisioner/main.tf via `source`.
# =============================================================================

locals {
  install_script = templatefile("${path.module}/templates/install_splunk_forwarder.sh", {
    s3_bucket              = var.s3_bucket
    s3_key                 = var.s3_key
    splunk_install_dir     = var.splunk_install_dir
    splunk_user            = var.splunk_user
    splunk_group           = var.splunk_group
    deployment_server      = var.deployment_server
    deployment_server_port = var.deployment_server_port
    splunk_admin_password  = var.splunk_admin_password
    aws_region             = var.aws_region
  })
}

# -----------------------------------------------------------------------------
# IAM Policy: allow EC2 instances to pull the Splunk package from S3
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "splunk_s3_read" {
  name        = "${var.name_prefix}-splunk-s3-read"
  description = "Allows EC2 instances to download the Splunk UF package from S3"
  tags        = var.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSplunkPackageRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket}/${var.s3_key}"
      },
      {
        Sid    = "AllowBucketList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket}"
        Condition = {
          StringLike = {
            "s3:prefix" = [dirname(var.s3_key)]
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SSM Document: Splunk Universal Forwarder installer (Linux only)
#
# Design decisions:
#   - schemaVersion 2.2 → RunCommand (not Automation), so it targets instances
#     directly and is triggered manually — never auto-applied.
#   - No EventBridge / Association resource is created here, so the document
#     CANNOT apply to existing or future servers automatically.
#   - Operator triggers this manually via AWS Console → Run Command, or CLI:
#       aws ssm send-command --document-name <name> --instance-ids <id> ...
# -----------------------------------------------------------------------------
resource "aws_ssm_document" "splunk_forwarder_install" {
  name            = "${var.name_prefix}-splunk-uf-install"
  document_type   = "Command"
  document_format = "JSON"
  tags            = var.tags

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Installs the Splunk Universal Forwarder on Linux EC2 instances. Trigger manually for new instances only — no automatic association."

    parameters = {
      S3Bucket = {
        type         = "String"
        description  = "S3 bucket containing the Splunk UF package."
        default      = var.s3_bucket
      }
      S3Key = {
        type         = "String"
        description  = "S3 object key (path) to the Splunk UF installer package."
        default      = var.s3_key
      }
      SplunkInstallDir = {
        type        = "String"
        description = "Base directory for Splunk installation."
        default     = var.splunk_install_dir
      }
      SplunkUser = {
        type        = "String"
        description = "OS user to run Splunk under."
        default     = var.splunk_user
      }
      SplunkGroup = {
        type        = "String"
        description = "OS group for the Splunk user."
        default     = var.splunk_group
      }
      DeploymentServer = {
        type        = "String"
        description = "Splunk Deployment Server hostname or IP."
        default     = var.deployment_server
      }
      DeploymentServerPort = {
        type        = "String"
        description = "Splunk Deployment Server port (default 8089)."
        default     = tostring(var.deployment_server_port)
      }
      SplunkAdminPassword = {
        type        = "String"
        description = "Splunk admin seed password (use SSM Parameter Store reference in production)."
        default     = var.splunk_admin_password
      }
      AWSRegion = {
        type        = "String"
        description = "AWS region used for S3 download."
        default     = var.aws_region
      }
    }

    mainSteps = [
      # -----------------------------------------------------------------------
      # Step 1: Validate this is a Linux instance
      # -----------------------------------------------------------------------
      {
        action = "aws:runShellScript"
        name   = "ValidateLinux"
        precondition = {
          StringEquals = ["platformType", "Linux"]
        }
        inputs = {
          timeoutSeconds = "30"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "echo '[INFO] Platform check passed: Linux confirmed.'",
            "uname -a"
          ]
        }
      },

      # -----------------------------------------------------------------------
      # Step 2: Verify Splunk is NOT already installed (idempotency guard)
      # -----------------------------------------------------------------------
      {
        action = "aws:runShellScript"
        name   = "CheckNotInstalled"
        precondition = {
          StringEquals = ["platformType", "Linux"]
        }
        inputs = {
          timeoutSeconds = "30"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "if [ -d '{{ SplunkInstallDir }}/splunkforwarder' ]; then",
            "  echo '[SKIP] Splunk Universal Forwarder already installed. Exiting.'",
            "  exit 1",
            "fi",
            "echo '[INFO] No existing Splunk installation found. Proceeding.'"
          ]
        }
      },

      # -----------------------------------------------------------------------
      # Step 3: Run the full installation shell script (from templates/)
      # -----------------------------------------------------------------------
      {
        action = "aws:runShellScript"
        name   = "InstallSplunkForwarder"
        precondition = {
          StringEquals = ["platformType", "Linux"]
        }
        inputs = {
          timeoutSeconds = "600"
          runCommand     = split("\n", local.install_script)
        }
      },

      # -----------------------------------------------------------------------
      # Step 4: Post-install verification
      # -----------------------------------------------------------------------
      {
        action = "aws:runShellScript"
        name   = "VerifyInstallation"
        precondition = {
          StringEquals = ["platformType", "Linux"]
        }
        inputs = {
          timeoutSeconds = "60"
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "echo '[INFO] Verifying SplunkForwarder service status...'",
            "systemctl is-active --quiet SplunkForwarder && echo '[OK] SplunkForwarder is active.' || { echo '[ERROR] SplunkForwarder is not running.'; exit 1; }",
            "echo '[INFO] Verifying deployment server config...'",
            "cat '{{ SplunkInstallDir }}/splunkforwarder/etc/system/local/deploymentclient.conf' || true",
            "echo '[INFO] Installation verification complete.'"
          ]
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SSM Parameter: store the document name for cross-stack reference
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "splunk_ssm_doc_name" {
  name  = "/splunk/ssm-document-name"
  type  = "String"
  value = aws_ssm_document.splunk_forwarder_install.name
  tags  = var.tags
}
