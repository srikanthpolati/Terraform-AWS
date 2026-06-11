###############################################################################
# SSM Linux Module
# Manages: Distributor packages, State Manager associations,
#          Inventory collection, and Compliance for Linux EC2 instances
###############################################################################

###############################################################################
# 1. SSM DISTRIBUTOR - Package definitions (one per application)
#    Each document references the S3-hosted install package.
#    Package zip files must be uploaded to S3 separately (see README).
###############################################################################

resource "aws_ssm_document" "linux_splunk_uf" {
  name            = "${var.environment}-linux-splunk-uf-package"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.mandatory_app_versions["splunk_uf"]
    publisher     = "Internal"
    description   = "Splunk Universal Forwarder for Linux"
    packages = {
      amazon = {
        "x86_64" = {
          file = "splunk-uf-linux-${var.mandatory_app_versions["splunk_uf"]}.zip"
        }
        "arm64" = {
          file = "splunk-uf-linux-arm64-${var.mandatory_app_versions["splunk_uf"]}.zip"
        }
      }
      _any = {
        "x86_64" = {
          file = "splunk-uf-linux-${var.mandatory_app_versions["splunk_uf"]}.zip"
        }
        "arm64" = {
          file = "splunk-uf-linux-arm64-${var.mandatory_app_versions["splunk_uf"]}.zip"
        }
      }
    }
    files = {
      "splunk-uf-linux-${var.mandatory_app_versions["splunk_uf"]}.zip" = {
        checksums = {
          sha256 = "REPLACE_WITH_ACTUAL_SHA256_AFTER_UPLOADING_PACKAGE"
        }
        size = 0
        s3Location = {
          bucket = var.s3_bucket_id
          key    = "linux/splunk-uf/splunk-uf-linux-${var.mandatory_app_versions["splunk_uf"]}.zip"
        }
      }
    }
  })

  tags = merge(var.common_tags, { Application = "splunk-uf", OS = "linux" })
}

resource "aws_ssm_document" "linux_qualys_agent" {
  name            = "${var.environment}-linux-qualys-agent-package"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.mandatory_app_versions["qualys_agent"]
    publisher     = "Internal"
    description   = "Qualys Cloud Agent for Linux"
    packages = {
      _any = {
        "x86_64" = {
          file = "qualys-cloud-agent-linux-${var.mandatory_app_versions["qualys_agent"]}.zip"
        }
      }
    }
    files = {
      "qualys-cloud-agent-linux-${var.mandatory_app_versions["qualys_agent"]}.zip" = {
        checksums = {
          sha256 = "REPLACE_WITH_ACTUAL_SHA256_AFTER_UPLOADING_PACKAGE"
        }
        size = 0
        s3Location = {
          bucket = var.s3_bucket_id
          key    = "linux/qualys-agent/qualys-cloud-agent-linux-${var.mandatory_app_versions["qualys_agent"]}.zip"
        }
      }
    }
  })

  tags = merge(var.common_tags, { Application = "qualys-agent", OS = "linux" })
}

resource "aws_ssm_document" "linux_cloudwatch_agent" {
  name            = "${var.environment}-linux-cloudwatch-agent-package"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.mandatory_app_versions["cloudwatch"]
    publisher     = "Amazon"
    description   = "AWS CloudWatch Agent for Linux - managed via SSM Distributor"
    packages = {
      amazon = {
        "x86_64" = { file = "amazon-cloudwatch-agent-linux.zip" }
        "arm64"  = { file = "amazon-cloudwatch-agent-linux-arm64.zip" }
      }
      _any = {
        "x86_64" = { file = "amazon-cloudwatch-agent-linux.zip" }
      }
    }
    files = {
      "amazon-cloudwatch-agent-linux.zip" = {
        checksums = {
          sha256 = "REPLACE_WITH_ACTUAL_SHA256_AFTER_UPLOADING_PACKAGE"
        }
        size = 0
        s3Location = {
          bucket = var.s3_bucket_id
          key    = "linux/cloudwatch-agent/amazon-cloudwatch-agent-linux-${var.mandatory_app_versions["cloudwatch"]}.zip"
        }
      }
    }
  })

  tags = merge(var.common_tags, { Application = "cloudwatch-agent", OS = "linux" })
}

resource "aws_ssm_document" "linux_carbonblack_agent" {
  name            = "${var.environment}-linux-carbonblack-agent-package"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.mandatory_app_versions["carbonblack"]
    publisher     = "Internal"
    description   = "CarbonBlack CBC Sensor for Linux"
    packages = {
      _any = {
        "x86_64" = {
          file = "carbonblack-linux-${var.mandatory_app_versions["carbonblack"]}.zip"
        }
      }
    }
    files = {
      "carbonblack-linux-${var.mandatory_app_versions["carbonblack"]}.zip" = {
        checksums = {
          sha256 = "REPLACE_WITH_ACTUAL_SHA256_AFTER_UPLOADING_PACKAGE"
        }
        size = 0
        s3Location = {
          bucket = var.s3_bucket_id
          key    = "linux/carbonblack/carbonblack-linux-${var.mandatory_app_versions["carbonblack"]}.zip"
        }
      }
    }
  })

  tags = merge(var.common_tags, { Application = "carbonblack-agent", OS = "linux" })
}

###############################################################################
# 2. SSM DOCUMENTS - Installation run commands
#    These Command documents are used by State Manager to install each agent.
#    They read the target version from Parameter Store at execution time,
#    check if the correct version is installed, and install/upgrade if not.
###############################################################################

resource "aws_ssm_document" "linux_install_splunk_uf" {
  name            = "${var.environment}-linux-install-splunk-uf"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Install or upgrade Splunk Universal Forwarder on Linux to target version"
    parameters:
      TargetVersion:
        type: String
        description: "Target Splunk UF version"
        default: "${var.mandatory_app_versions["splunk_uf"]}"
      DeploymentServer:
        type: String
        description: "Splunk Deployment Server URI"
        default: "${var.splunk_deployment_server}"
    mainSteps:
      - action: aws:runShellScript
        name: CheckAndInstallSplunkUF
        inputs:
          runCommand:
            - |
              #!/bin/bash
              set -euo pipefail
              TARGET_VERSION="{{ TargetVersion }}"
              DEPLOYMENT_SERVER="{{ DeploymentServer }}"
              SPLUNK_HOME="/opt/splunkforwarder"
              INSTALL_DIR="/tmp/splunk-install"

              echo "==> Checking Splunk Universal Forwarder installation..."

              # Detect current version if installed
              if [ -f "$SPLUNK_HOME/bin/splunk" ]; then
                CURRENT_VERSION=$($SPLUNK_HOME/bin/splunk version --accept-license --answer-yes 2>/dev/null | grep -oP 'Splunk Universal Forwarder \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
                echo "==> Current version: $CURRENT_VERSION, Target: $TARGET_VERSION"
                if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
                  echo "==> Splunk UF $TARGET_VERSION already installed. Ensuring service is running..."
                  $SPLUNK_HOME/bin/splunk start --accept-license --answer-yes || true
                  exit 0
                fi
                echo "==> Version mismatch. Upgrading from $CURRENT_VERSION to $TARGET_VERSION..."
              else
                echo "==> Splunk UF not installed. Installing version $TARGET_VERSION..."
              fi

              mkdir -p "$INSTALL_DIR"
              cd "$INSTALL_DIR"

              # Detect architecture
              ARCH=$(uname -m)
              if [ "$ARCH" = "aarch64" ]; then
                PKG_ARCH="arm64"
              else
                PKG_ARCH="x86_64"
              fi

              # Detect package manager and download appropriate package
              if command -v rpm &>/dev/null; then
                PKG_URL="https://download.splunk.com/products/universalforwarder/releases/${TARGET_VERSION}/linux/splunkforwarder-${TARGET_VERSION}-linux-${PKG_ARCH}.rpm"
                aws s3 cp "s3://${var.s3_bucket_id}/linux/splunk-uf/splunkforwarder-${TARGET_VERSION}-${PKG_ARCH}.rpm" ./splunkforwarder.rpm 2>/dev/null || \
                  curl -L -o splunkforwarder.rpm "$PKG_URL"
                rpm -Uvh ./splunkforwarder.rpm
              elif command -v dpkg &>/dev/null; then
                PKG_URL="https://download.splunk.com/products/universalforwarder/releases/${TARGET_VERSION}/linux/splunkforwarder-${TARGET_VERSION}-linux-${PKG_ARCH}.deb"
                aws s3 cp "s3://${var.s3_bucket_id}/linux/splunk-uf/splunkforwarder-${TARGET_VERSION}-${PKG_ARCH}.deb" ./splunkforwarder.deb 2>/dev/null || \
                  curl -L -o splunkforwarder.deb "$PKG_URL"
                dpkg -i ./splunkforwarder.deb
              fi

              # Configure deployment server
              $SPLUNK_HOME/bin/splunk start --accept-license --answer-yes
              $SPLUNK_HOME/bin/splunk set deploy-poll "$DEPLOYMENT_SERVER" -auth admin:changeme || true
              $SPLUNK_HOME/bin/splunk enable boot-start -user splunk --accept-license --answer-yes || true
              $SPLUNK_HOME/bin/splunk restart || true

              echo "==> Splunk UF $TARGET_VERSION installation complete."
              rm -rf "$INSTALL_DIR"
  YAML

  tags = merge(var.common_tags, { Application = "splunk-uf", OS = "linux" })
}

resource "aws_ssm_document" "linux_install_qualys_agent" {
  name            = "${var.environment}-linux-install-qualys-agent"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Install or upgrade Qualys Cloud Agent on Linux to target version"
    parameters:
      TargetVersion:
        type: String
        default: "${var.mandatory_app_versions["qualys_agent"]}"
      ActivationId:
        type: String
        default: "${var.qualys_activation_id}"
      CustomerId:
        type: String
        default: "${var.qualys_customer_id}"
    mainSteps:
      - action: aws:runShellScript
        name: CheckAndInstallQualysAgent
        inputs:
          runCommand:
            - |
              #!/bin/bash
              set -euo pipefail
              TARGET_VERSION="{{ TargetVersion }}"
              ACTIVATION_ID="{{ ActivationId }}"
              CUSTOMER_ID="{{ CustomerId }}"
              QUALYS_AGENT="/usr/local/qualys/cloud-agent/bin/qualys-cloud-agent"

              echo "==> Checking Qualys Cloud Agent installation..."

              if [ -f "$QUALYS_AGENT" ]; then
                CURRENT_VERSION=$($QUALYS_AGENT --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
                echo "==> Current: $CURRENT_VERSION, Target: $TARGET_VERSION"
                if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
                  echo "==> Qualys agent $TARGET_VERSION already installed. Verifying service..."
                  systemctl is-active --quiet qualys-cloud-agent || systemctl start qualys-cloud-agent
                  exit 0
                fi
              else
                echo "==> Qualys agent not found. Installing $TARGET_VERSION..."
              fi

              INSTALL_DIR="/tmp/qualys-install"
              mkdir -p "$INSTALL_DIR"
              cd "$INSTALL_DIR"

              # Try S3 first (corporate package repo), fallback to Qualys CDN
              if command -v rpm &>/dev/null; then
                aws s3 cp "s3://${var.s3_bucket_id}/linux/qualys-agent/qualys-cloud-agent-${TARGET_VERSION}.rpm" ./qualys.rpm 2>/dev/null || \
                  curl -L -o qualys.rpm "https://www.qualys.com/qagent/qualys-cloud-agent.x86_64.rpm"
                rpm -ivh ./qualys.rpm 2>/dev/null || rpm -Uvh ./qualys.rpm
              elif command -v dpkg &>/dev/null; then
                aws s3 cp "s3://${var.s3_bucket_id}/linux/qualys-agent/qualys-cloud-agent-${TARGET_VERSION}.deb" ./qualys.deb 2>/dev/null || \
                  curl -L -o qualys.deb "https://www.qualys.com/qagent/qualys-cloud-agent.x86_64.deb"
                dpkg -i ./qualys.deb
              fi

              # Activate the agent
              /usr/local/qualys/cloud-agent/bin/qualys-cloud-agent.sh ActivationId="$ACTIVATION_ID" CustomerId="$CUSTOMER_ID"

              systemctl enable qualys-cloud-agent
              systemctl start qualys-cloud-agent

              echo "==> Qualys Cloud Agent $TARGET_VERSION installed and activated."
              rm -rf "$INSTALL_DIR"
  YAML

  tags = merge(var.common_tags, { Application = "qualys-agent", OS = "linux" })
}

resource "aws_ssm_document" "linux_install_cloudwatch_agent" {
  name            = "${var.environment}-linux-install-cloudwatch-agent"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Install or upgrade AWS CloudWatch Agent on Linux to target version"
    parameters:
      TargetVersion:
        type: String
        default: "${var.mandatory_app_versions["cloudwatch"]}"
    mainSteps:
      - action: aws:runShellScript
        name: CheckAndInstallCloudWatchAgent
        inputs:
          runCommand:
            - |
              #!/bin/bash
              set -euo pipefail
              TARGET_VERSION="{{ TargetVersion }}"
              CWA_BIN="/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent"

              echo "==> Checking CloudWatch Agent installation..."

              if [ -f "$CWA_BIN" ]; then
                CURRENT_VERSION=$($CWA_BIN --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
                echo "==> Current: $CURRENT_VERSION, Target: $TARGET_VERSION"
                if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
                  echo "==> CloudWatch Agent $TARGET_VERSION already installed. Verifying service..."
                  systemctl is-active --quiet amazon-cloudwatch-agent || \
                    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start
                  exit 0
                fi
              else
                echo "==> CloudWatch Agent not found. Installing $TARGET_VERSION..."
              fi

              ARCH=$(uname -m)
              REGION=$(curl -s --connect-timeout 3 http://169.254.169.254/latest/meta-data/placement/region || echo "ap-southeast-2")
              INSTALL_DIR="/tmp/cwa-install"
              mkdir -p "$INSTALL_DIR"
              cd "$INSTALL_DIR"

              if command -v rpm &>/dev/null; then
                aws s3 cp "s3://amazoncloudwatch-agent-$REGION/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm" ./cwa.rpm 2>/dev/null || \
                  aws ssm get-parameter --name "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2" --region "$REGION" &>/dev/null && \
                  yum install -y amazon-cloudwatch-agent 2>/dev/null || \
                  curl -L -o cwa.rpm "https://s3.amazonaws.com/amazoncloudwatch-agent/redhat/amd64/latest/amazon-cloudwatch-agent.rpm"
                rpm -Uvh ./cwa.rpm 2>/dev/null || true
              elif command -v dpkg &>/dev/null; then
                curl -L -o cwa.deb "https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
                dpkg -i ./cwa.deb
              fi

              # Apply SSM-stored CloudWatch config if present
              aws ssm get-parameter \
                --name "/mandatory-apps/cloudwatch-agent-config/linux" \
                --query "Parameter.Value" --output text 2>/dev/null > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || \
                echo "==> No custom CWA config found in SSM; using default."

              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config -m ec2 \
                -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json 2>/dev/null || \
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config -m ec2 -s -c ssm:/mandatory-apps/cloudwatch-agent-config/linux 2>/dev/null || true

              systemctl enable amazon-cloudwatch-agent
              systemctl start amazon-cloudwatch-agent || true

              echo "==> CloudWatch Agent installation complete."
              rm -rf "$INSTALL_DIR"
  YAML

  tags = merge(var.common_tags, { Application = "cloudwatch-agent", OS = "linux" })
}

resource "aws_ssm_document" "linux_install_carbonblack" {
  name            = "${var.environment}-linux-install-carbonblack"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Install or upgrade CarbonBlack CBC Sensor on Linux to target version"
    parameters:
      TargetVersion:
        type: String
        default: "${var.mandatory_app_versions["carbonblack"]}"
      ServerUrl:
        type: String
        default: "${var.carbonblack_server_url}"
      GroupName:
        type: String
        default: "${var.carbonblack_group_name}"
    mainSteps:
      - action: aws:runShellScript
        name: CheckAndInstallCarbonBlack
        inputs:
          runCommand:
            - |
              #!/bin/bash
              set -euo pipefail
              TARGET_VERSION="{{ TargetVersion }}"
              SERVER_URL="{{ ServerUrl }}"
              GROUP_NAME="{{ GroupName }}"

              echo "==> Checking CarbonBlack CBC Sensor installation..."

              if command -v cbcsensor &>/dev/null || [ -f "/usr/lib/cb/cbcsensor" ]; then
                CURRENT_VERSION=$(rpm -q --queryformat "%{VERSION}" cb-psc-sensor 2>/dev/null || \
                                  dpkg -l cb-psc-sensor 2>/dev/null | awk '/^ii/ {print $3}' || echo "unknown")
                echo "==> Current: $CURRENT_VERSION, Target: $TARGET_VERSION"
                if [[ "$CURRENT_VERSION" == *"$TARGET_VERSION"* ]]; then
                  echo "==> CarbonBlack $TARGET_VERSION already installed."
                  exit 0
                fi
              else
                echo "==> CarbonBlack not found. Installing $TARGET_VERSION..."
              fi

              INSTALL_DIR="/tmp/cb-install"
              mkdir -p "$INSTALL_DIR"
              cd "$INSTALL_DIR"

              # Retrieve registration token from SSM Parameter Store
              CBC_REG_TOKEN=$(aws ssm get-parameter \
                --name "/mandatory-apps/carbonblack/registration-token" \
                --with-decryption \
                --query "Parameter.Value" \
                --output text 2>/dev/null || echo "")

              # Fetch package from S3
              if command -v rpm &>/dev/null; then
                aws s3 cp "s3://${var.s3_bucket_id}/linux/carbonblack/cb-psc-sensor-${TARGET_VERSION}.rpm" ./cb-sensor.rpm
                rpm -ivh ./cb-sensor.rpm 2>/dev/null || rpm -Uvh ./cb-sensor.rpm
              elif command -v dpkg &>/dev/null; then
                aws s3 cp "s3://${var.s3_bucket_id}/linux/carbonblack/cb-psc-sensor_${TARGET_VERSION}.deb" ./cb-sensor.deb
                dpkg -i ./cb-sensor.deb
              fi

              # Register sensor if token is available
              if [ -n "$CBC_REG_TOKEN" ]; then
                /usr/lib/cb/cbcsensor --register-with-token "$CBC_REG_TOKEN" --server-url "$SERVER_URL" --group "$GROUP_NAME" || true
              else
                echo "==> WARNING: No registration token found at /mandatory-apps/carbonblack/registration-token"
              fi

              systemctl enable cbcsensor
              systemctl start cbcsensor || true

              echo "==> CarbonBlack $TARGET_VERSION installation complete."
              rm -rf "$INSTALL_DIR"
  YAML

  tags = merge(var.common_tags, { Application = "carbonblack-agent", OS = "linux" })
}

###############################################################################
# 3. SSM COMPLIANCE - Custom compliance items
#    One compliance item per application. Instances report compliant when
#    the correct version is detected, non-compliant otherwise.
#    Compliance data surfaces in SSM Compliance > Custom.
###############################################################################

resource "aws_ssm_document" "linux_compliance_check" {
  name            = "${var.environment}-linux-mandatory-apps-compliance"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Evaluate compliance for all mandatory applications on Linux and report to SSM Compliance"
    parameters:
      SplunkVersion:
        type: String
        default: "${var.mandatory_app_versions["splunk_uf"]}"
      QualysVersion:
        type: String
        default: "${var.mandatory_app_versions["qualys_agent"]}"
      CloudWatchVersion:
        type: String
        default: "${var.mandatory_app_versions["cloudwatch"]}"
      CarbonBlackVersion:
        type: String
        default: "${var.mandatory_app_versions["carbonblack"]}"
    mainSteps:
      - action: aws:runShellScript
        name: EvaluateMandatoryAppsCompliance
        inputs:
          runCommand:
            - |
              #!/bin/bash
              INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
              REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
              COMPLIANCE_TYPE="MandatoryApplications"
              OVERALL_STATUS=0

              put_compliance() {
                local app_name=$1
                local status=$2   # COMPLIANT or NON_COMPLIANT
                local detail=$3
                aws ssm put-compliance-items \
                  --resource-id "$INSTANCE_ID" \
                  --resource-type ManagedInstance \
                  --compliance-type "$COMPLIANCE_TYPE" \
                  --execution-summary "ExecutionTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                  --items "Id=$app_name,Title=$app_name,Severity=CRITICAL,Status=$status,Details={Comment='$detail'}" \
                  --region "$REGION" || true
              }

              # --- Splunk Universal Forwarder ---
              TARGET="{{ SplunkVersion }}"
              SPLUNK_BIN="/opt/splunkforwarder/bin/splunk"
              if [ -f "$SPLUNK_BIN" ]; then
                CURRENT=$($SPLUNK_BIN version --accept-license --answer-yes 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
                if [ "$CURRENT" = "$TARGET" ]; then
                  put_compliance "SplunkUniversalForwarder" "COMPLIANT" "Version $CURRENT matches target $TARGET"
                else
                  put_compliance "SplunkUniversalForwarder" "NON_COMPLIANT" "Installed=$CURRENT Expected=$TARGET"
                  OVERALL_STATUS=1
                fi
              else
                put_compliance "SplunkUniversalForwarder" "NON_COMPLIANT" "Not installed. Target=$TARGET"
                OVERALL_STATUS=1
              fi

              # --- Qualys Cloud Agent ---
              TARGET="{{ QualysVersion }}"
              QUALYS_BIN="/usr/local/qualys/cloud-agent/bin/qualys-cloud-agent"
              if [ -f "$QUALYS_BIN" ]; then
                CURRENT=$($QUALYS_BIN --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
                if [ "$CURRENT" = "$TARGET" ]; then
                  put_compliance "QualysCloudAgent" "COMPLIANT" "Version $CURRENT matches target $TARGET"
                else
                  put_compliance "QualysCloudAgent" "NON_COMPLIANT" "Installed=$CURRENT Expected=$TARGET"
                  OVERALL_STATUS=1
                fi
              else
                put_compliance "QualysCloudAgent" "NON_COMPLIANT" "Not installed. Target=$TARGET"
                OVERALL_STATUS=1
              fi

              # --- CloudWatch Agent ---
              TARGET="{{ CloudWatchVersion }}"
              CWA_BIN="/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent"
              if [ -f "$CWA_BIN" ]; then
                CURRENT=$($CWA_BIN --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
                if [ "$CURRENT" = "$TARGET" ]; then
                  put_compliance "CloudWatchAgent" "COMPLIANT" "Version $CURRENT matches target $TARGET"
                else
                  put_compliance "CloudWatchAgent" "NON_COMPLIANT" "Installed=$CURRENT Expected=$TARGET"
                  OVERALL_STATUS=1
                fi
              else
                put_compliance "CloudWatchAgent" "NON_COMPLIANT" "Not installed. Target=$TARGET"
                OVERALL_STATUS=1
              fi

              # --- CarbonBlack CBC Sensor ---
              TARGET="{{ CarbonBlackVersion }}"
              if command -v cbcsensor &>/dev/null || [ -f "/usr/lib/cb/cbcsensor" ]; then
                CURRENT=$(rpm -q --queryformat "%{VERSION}" cb-psc-sensor 2>/dev/null || \
                          dpkg -l cb-psc-sensor 2>/dev/null | awk '/^ii/ {print $3}' || echo "unknown")
                if [[ "$CURRENT" == *"$TARGET"* ]]; then
                  put_compliance "CarbonBlackCBCSensor" "COMPLIANT" "Version $CURRENT matches target $TARGET"
                else
                  put_compliance "CarbonBlackCBCSensor" "NON_COMPLIANT" "Installed=$CURRENT Expected=$TARGET"
                  OVERALL_STATUS=1
                fi
              else
                put_compliance "CarbonBlackCBCSensor" "NON_COMPLIANT" "Not installed. Target=$TARGET"
                OVERALL_STATUS=1
              fi

              echo "==> Compliance check complete. Non-compliant items: $OVERALL_STATUS"
              exit 0
  YAML

  tags = merge(var.common_tags, { OS = "linux", Purpose = "compliance-reporting" })
}

###############################################################################
# 4. SSM INVENTORY - Association to collect application metadata
#    Gathers installed application data every 30 minutes from Linux instances.
#    Visible under SSM > Fleet Manager > Inventory.
###############################################################################

resource "aws_ssm_association" "linux_inventory" {
  name             = "AWS-GatherSoftwareInventory"
  association_name = "${var.environment}-linux-mandatory-apps-inventory"

  schedule_expression = "rate(30 minutes)"

  targets {
    key    = var.linux_target_key
    values = var.linux_target_values
  }

  parameters = {
    applications         = "Enabled"
    awsComponents        = "Enabled"
    customInventory      = "Enabled"
    instanceDetailedInfo = "Enabled"
    networkConfig        = "Disabled"
    services             = "Enabled"
    windowsRoles         = "Disabled"
  }

  sync_compliance = "AUTO"

  tags = merge(var.common_tags, { OS = "linux", Purpose = "inventory" })
}

###############################################################################
# 5. SSM STATE MANAGER - Enforcement associations
#    One association per application. Each runs on schedule and also at
#    instance startup (ApplyOnlyAtCronInterval = false).
#    If the app is missing/wrong version → installs/upgrades automatically.
###############################################################################

resource "aws_ssm_association" "linux_install_splunk_uf" {
  name             = aws_ssm_document.linux_install_splunk_uf.name
  association_name = "${var.environment}-linux-enforce-splunk-uf"

  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false   # Also runs at instance registration/startup

  targets {
    key    = var.linux_target_key
    values = var.linux_target_values
  }

  parameters = {
    TargetVersion    = var.mandatory_app_versions["splunk_uf"]
    DeploymentServer = var.splunk_deployment_server
  }

  max_errors     = "10%"
  max_concurrency = "20%"

  compliance_severity = "CRITICAL"

  output_location {
    s3_bucket_name = var.s3_bucket_id
    s3_key_prefix  = "ssm-output/linux/splunk-uf"
  }

  tags = merge(var.common_tags, { Application = "splunk-uf", OS = "linux" })
}

resource "aws_ssm_association" "linux_install_qualys_agent" {
  name             = aws_ssm_document.linux_install_qualys_agent.name
  association_name = "${var.environment}-linux-enforce-qualys-agent"

  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false

  targets {
    key    = var.linux_target_key
    values = var.linux_target_values
  }

  parameters = {
    TargetVersion = var.mandatory_app_versions["qualys_agent"]
    ActivationId  = var.qualys_activation_id
    CustomerId    = var.qualys_customer_id
  }

  max_errors      = "10%"
  max_concurrency = "20%"
  compliance_severity = "CRITICAL"

  output_location {
    s3_bucket_name = var.s3_bucket_id
    s3_key_prefix  = "ssm-output/linux/qualys-agent"
  }

  tags = merge(var.common_tags, { Application = "qualys-agent", OS = "linux" })
}

resource "aws_ssm_association" "linux_install_cloudwatch_agent" {
  name             = aws_ssm_document.linux_install_cloudwatch_agent.name
  association_name = "${var.environment}-linux-enforce-cloudwatch-agent"

  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false

  targets {
    key    = var.linux_target_key
    values = var.linux_target_values
  }

  parameters = {
    TargetVersion = var.mandatory_app_versions["cloudwatch"]
  }

  max_errors      = "10%"
  max_concurrency = "20%"
  compliance_severity = "CRITICAL"

  output_location {
    s3_bucket_name = var.s3_bucket_id
    s3_key_prefix  = "ssm-output/linux/cloudwatch-agent"
  }

  tags = merge(var.common_tags, { Application = "cloudwatch-agent", OS = "linux" })
}

resource "aws_ssm_association" "linux_install_carbonblack" {
  name             = aws_ssm_document.linux_install_carbonblack.name
  association_name = "${var.environment}-linux-enforce-carbonblack"

  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false

  targets {
    key    = var.linux_target_key
    values = var.linux_target_values
  }

  parameters = {
    TargetVersion = var.mandatory_app_versions["carbonblack"]
    ServerUrl     = var.carbonblack_server_url
    GroupName     = var.carbonblack_group_name
  }

  max_errors      = "10%"
  max_concurrency = "20%"
  compliance_severity = "CRITICAL"

  output_location {
    s3_bucket_name = var.s3_bucket_id
    s3_key_prefix  = "ssm-output/linux/carbonblack"
  }

  tags = merge(var.common_tags, { Application = "carbonblack-agent", OS = "linux" })
}

# Compliance reporting association - runs after installs to update compliance status
resource "aws_ssm_association" "linux_compliance_check" {
  name             = aws_ssm_document.linux_compliance_check.name
  association_name = "${var.environment}-linux-compliance-report"

  # Run compliance check shortly after the install schedule runs
  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false

  targets {
    key    = var.linux_target_key
    values = var.linux_target_values
  }

  parameters = {
    SplunkVersion     = var.mandatory_app_versions["splunk_uf"]
    QualysVersion     = var.mandatory_app_versions["qualys_agent"]
    CloudWatchVersion = var.mandatory_app_versions["cloudwatch"]
    CarbonBlackVersion = var.mandatory_app_versions["carbonblack"]
  }

  max_errors      = "25%"
  max_concurrency = "50%"
  compliance_severity = "CRITICAL"

  output_location {
    s3_bucket_name = var.s3_bucket_id
    s3_key_prefix  = "ssm-output/linux/compliance"
  }

  tags = merge(var.common_tags, { OS = "linux", Purpose = "compliance" })
}
