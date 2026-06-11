###############################################################################
# SSM Windows Module
# Manages: Distributor packages, State Manager associations,
#          Inventory collection, and Compliance for Windows EC2 instances
###############################################################################

###############################################################################
# 1. SSM DISTRIBUTOR - Package definitions for Windows
###############################################################################

resource "aws_ssm_document" "windows_splunk_uf" {
  name            = "${var.environment}-windows-splunk-uf-package"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.mandatory_app_versions["splunk_uf"]
    publisher     = "Internal"
    description   = "Splunk Universal Forwarder for Windows"
    packages = {
      windows = {
        "x86_64" = {
          file = "splunk-uf-windows-${var.mandatory_app_versions["splunk_uf"]}.zip"
        }
      }
    }
    files = {
      "splunk-uf-windows-${var.mandatory_app_versions["splunk_uf"]}.zip" = {
        checksums = {
          sha256 = "REPLACE_WITH_ACTUAL_SHA256_AFTER_UPLOADING_PACKAGE"
        }
        size = 0
        s3Location = {
          bucket = var.s3_bucket_id
          key    = "windows/splunk-uf/splunk-uf-windows-${var.mandatory_app_versions["splunk_uf"]}.zip"
        }
      }
    }
  })

  tags = merge(var.common_tags, { Application = "splunk-uf", OS = "windows" })
}

resource "aws_ssm_document" "windows_qualys_agent" {
  name            = "${var.environment}-windows-qualys-agent-package"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.mandatory_app_versions["qualys_agent"]
    publisher     = "Internal"
    description   = "Qualys Cloud Agent for Windows"
    packages = {
      windows = {
        "x86_64" = {
          file = "qualys-cloud-agent-windows-${var.mandatory_app_versions["qualys_agent"]}.zip"
        }
      }
    }
    files = {
      "qualys-cloud-agent-windows-${var.mandatory_app_versions["qualys_agent"]}.zip" = {
        checksums = {
          sha256 = "REPLACE_WITH_ACTUAL_SHA256_AFTER_UPLOADING_PACKAGE"
        }
        size = 0
        s3Location = {
          bucket = var.s3_bucket_id
          key    = "windows/qualys-agent/qualys-cloud-agent-windows-${var.mandatory_app_versions["qualys_agent"]}.zip"
        }
      }
    }
  })

  tags = merge(var.common_tags, { Application = "qualys-agent", OS = "windows" })
}

resource "aws_ssm_document" "windows_cloudwatch_agent" {
  name            = "${var.environment}-windows-cloudwatch-agent-package"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.mandatory_app_versions["cloudwatch"]
    publisher     = "Amazon"
    description   = "AWS CloudWatch Agent for Windows"
    packages = {
      windows = {
        "x86_64" = {
          file = "amazon-cloudwatch-agent-windows.zip"
        }
      }
    }
    files = {
      "amazon-cloudwatch-agent-windows.zip" = {
        checksums = {
          sha256 = "REPLACE_WITH_ACTUAL_SHA256_AFTER_UPLOADING_PACKAGE"
        }
        size = 0
        s3Location = {
          bucket = var.s3_bucket_id
          key    = "windows/cloudwatch-agent/amazon-cloudwatch-agent-windows-${var.mandatory_app_versions["cloudwatch"]}.zip"
        }
      }
    }
  })

  tags = merge(var.common_tags, { Application = "cloudwatch-agent", OS = "windows" })
}

resource "aws_ssm_document" "windows_carbonblack_agent" {
  name            = "${var.environment}-windows-carbonblack-agent-package"
  document_type   = "Package"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.0"
    version       = var.mandatory_app_versions["carbonblack"]
    publisher     = "Internal"
    description   = "CarbonBlack CBC Sensor for Windows"
    packages = {
      windows = {
        "x86_64" = {
          file = "carbonblack-windows-${var.mandatory_app_versions["carbonblack"]}.zip"
        }
      }
    }
    files = {
      "carbonblack-windows-${var.mandatory_app_versions["carbonblack"]}.zip" = {
        checksums = {
          sha256 = "REPLACE_WITH_ACTUAL_SHA256_AFTER_UPLOADING_PACKAGE"
        }
        size = 0
        s3Location = {
          bucket = var.s3_bucket_id
          key    = "windows/carbonblack/carbonblack-windows-${var.mandatory_app_versions["carbonblack"]}.zip"
        }
      }
    }
  })

  tags = merge(var.common_tags, { Application = "carbonblack-agent", OS = "windows" })
}

###############################################################################
# 2. SSM DOCUMENTS - PowerShell installation commands for Windows
###############################################################################

resource "aws_ssm_document" "windows_install_splunk_uf" {
  name            = "${var.environment}-windows-install-splunk-uf"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Install or upgrade Splunk Universal Forwarder on Windows to target version"
    parameters:
      TargetVersion:
        type: String
        default: "${var.mandatory_app_versions["splunk_uf"]}"
      DeploymentServer:
        type: String
        default: "${var.splunk_deployment_server}"
    mainSteps:
      - action: aws:runPowerShellScript
        name: CheckAndInstallSplunkUF
        inputs:
          runCommand:
            - |
              $ErrorActionPreference = "Stop"
              $TargetVersion = "{{ TargetVersion }}"
              $DeploymentServer = "{{ DeploymentServer }}"
              $SplunkHome = "C:\Program Files\SplunkUniversalForwarder"
              $InstallDir = "C:\Temp\splunk-install"

              Write-Host "==> Checking Splunk Universal Forwarder installation..."

              $CurrentVersion = $null
              $SplunkExe = Join-Path $SplunkHome "bin\splunk.exe"

              if (Test-Path $SplunkExe) {
                try {
                  $VersionOutput = & $SplunkExe version 2>&1
                  if ($VersionOutput -match '(\d+\.\d+\.\d+)') {
                    $CurrentVersion = $Matches[1]
                  }
                } catch {}
              }

              if ($CurrentVersion -eq $TargetVersion) {
                Write-Host "==> Splunk UF $TargetVersion already installed. Verifying service..."
                $svc = Get-Service -Name "SplunkForwarder" -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -ne "Running") { Start-Service "SplunkForwarder" }
                exit 0
              }

              Write-Host "==> Installing/upgrading Splunk UF to $TargetVersion..."
              New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

              # Fetch MSI from S3 (preferred) or Splunk CDN
              $MsiPath = Join-Path $InstallDir "splunkforwarder.msi"
              try {
                $S3Key = "windows/splunk-uf/splunkforwarder-$TargetVersion-x64-release.msi"
                Read-S3Object -BucketName "${var.s3_bucket_id}" -Key $S3Key -File $MsiPath
              } catch {
                $DownloadUrl = "https://download.splunk.com/products/universalforwarder/releases/$TargetVersion/windows/splunkforwarder-$TargetVersion-x64-release.msi"
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $MsiPath -UseBasicParsing
              }

              $MsiArgs = @(
                "/i", $MsiPath,
                "/quiet",
                "/norestart",
                "AGREETOLICENSE=Yes",
                "DEPLOYMENT_SERVER=$DeploymentServer",
                "LAUNCHSPLUNK=1",
                "INSTALL_SHORTCUT=0"
              )
              $Result = Start-Process msiexec.exe -ArgumentList $MsiArgs -Wait -PassThru
              if ($Result.ExitCode -notin @(0, 1641, 3010)) {
                throw "MSI installation failed with exit code $($Result.ExitCode)"
              }

              Write-Host "==> Splunk UF $TargetVersion installation complete."
              Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
  YAML

  tags = merge(var.common_tags, { Application = "splunk-uf", OS = "windows" })
}

resource "aws_ssm_document" "windows_install_qualys_agent" {
  name            = "${var.environment}-windows-install-qualys-agent"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Install or upgrade Qualys Cloud Agent on Windows to target version"
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
      - action: aws:runPowerShellScript
        name: CheckAndInstallQualysAgent
        inputs:
          runCommand:
            - |
              $ErrorActionPreference = "Stop"
              $TargetVersion = "{{ TargetVersion }}"
              $ActivationId = "{{ ActivationId }}"
              $CustomerId = "{{ CustomerId }}"
              $InstallDir = "C:\Temp\qualys-install"

              Write-Host "==> Checking Qualys Cloud Agent installation..."

              $QualysProduct = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Qualys Cloud Agent*" }
              $CurrentVersion = $QualysProduct?.Version

              if ($CurrentVersion -eq $TargetVersion) {
                Write-Host "==> Qualys agent $TargetVersion already installed. Verifying service..."
                $svc = Get-Service -Name "QualysAgent" -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -ne "Running") { Start-Service "QualysAgent" }
                exit 0
              }

              Write-Host "==> Installing/upgrading Qualys agent to $TargetVersion..."
              New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

              $InstallerPath = Join-Path $InstallDir "QualysCloudAgent.exe"
              try {
                Read-S3Object -BucketName "${var.s3_bucket_id}" -Key "windows/qualys-agent/QualysCloudAgent-$TargetVersion.exe" -File $InstallerPath
              } catch {
                Invoke-WebRequest -Uri "https://www.qualys.com/qagent/windows/QualysCloudAgent.exe" -OutFile $InstallerPath -UseBasicParsing
              }

              $InstallArgs = "CustomerId={$CustomerId} ActivationId={$ActivationId} /quiet /norestart"
              $Result = Start-Process $InstallerPath -ArgumentList $InstallArgs -Wait -PassThru
              if ($Result.ExitCode -notin @(0, 3010)) {
                throw "Qualys installation failed with exit code $($Result.ExitCode)"
              }

              Write-Host "==> Qualys Cloud Agent $TargetVersion installed and activated."
              Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
  YAML

  tags = merge(var.common_tags, { Application = "qualys-agent", OS = "windows" })
}

resource "aws_ssm_document" "windows_install_cloudwatch_agent" {
  name            = "${var.environment}-windows-install-cloudwatch-agent"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Install or upgrade AWS CloudWatch Agent on Windows to target version"
    parameters:
      TargetVersion:
        type: String
        default: "${var.mandatory_app_versions["cloudwatch"]}"
    mainSteps:
      - action: aws:runPowerShellScript
        name: CheckAndInstallCloudWatchAgent
        inputs:
          runCommand:
            - |
              $ErrorActionPreference = "Stop"
              $TargetVersion = "{{ TargetVersion }}"
              $CWAPath = "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.exe"
              $InstallDir = "C:\Temp\cwa-install"

              Write-Host "==> Checking CloudWatch Agent installation..."

              if (Test-Path $CWAPath) {
                $FileVersion = (Get-Item $CWAPath).VersionInfo.FileVersion
                $CurrentVersion = ($FileVersion -split '\.')[0..2] -join '.'
                if ($CurrentVersion -eq $TargetVersion) {
                  Write-Host "==> CloudWatch Agent $TargetVersion already installed. Verifying service..."
                  $svc = Get-Service -Name "AmazonCloudWatchAgent" -ErrorAction SilentlyContinue
                  if ($svc -and $svc.Status -ne "Running") { Start-Service "AmazonCloudWatchAgent" }
                  exit 0
                }
              }

              Write-Host "==> Installing/upgrading CloudWatch Agent to $TargetVersion..."
              New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

              $MsiPath = Join-Path $InstallDir "amazon-cloudwatch-agent.msi"
              $Region = (Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/placement/region" -UseBasicParsing -TimeoutSec 3) 2>/dev/null
              if (-not $Region) { $Region = "${var.aws_region}" }

              $S3Url = "https://s3.$Region.amazonaws.com/amazoncloudwatch-agent-$Region/windows/amd64/latest/amazon-cloudwatch-agent.msi"
              try {
                Read-S3Object -BucketName "${var.s3_bucket_id}" -Key "windows/cloudwatch-agent/amazon-cloudwatch-agent-$TargetVersion.msi" -File $MsiPath
              } catch {
                Invoke-WebRequest -Uri $S3Url -OutFile $MsiPath -UseBasicParsing
              }

              $Result = Start-Process msiexec.exe -ArgumentList "/i", $MsiPath, "/quiet", "/norestart" -Wait -PassThru
              if ($Result.ExitCode -notin @(0, 1641, 3010)) {
                throw "CloudWatch Agent MSI failed with exit code $($Result.ExitCode)"
              }

              # Apply SSM-stored config if present
              try {
                $Config = (Get-SSMParameter -Name "/mandatory-apps/cloudwatch-agent-config/windows" -WithDecryption $false).Value
                $Config | Out-File "C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -Encoding UTF8
                & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" `
                  -Action fetch-config -Mode ec2 -ConfigLocation "file:C:\ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -Start
              } catch {
                Write-Host "==> No custom CWA config in SSM or config apply failed; starting with defaults."
                & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -Action start
              }

              Write-Host "==> CloudWatch Agent installation complete."
              Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
  YAML

  tags = merge(var.common_tags, { Application = "cloudwatch-agent", OS = "windows" })
}

resource "aws_ssm_document" "windows_install_carbonblack" {
  name            = "${var.environment}-windows-install-carbonblack"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Install or upgrade CarbonBlack CBC Sensor on Windows to target version"
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
      - action: aws:runPowerShellScript
        name: CheckAndInstallCarbonBlack
        inputs:
          runCommand:
            - |
              $ErrorActionPreference = "Stop"
              $TargetVersion = "{{ TargetVersion }}"
              $ServerUrl = "{{ ServerUrl }}"
              $GroupName = "{{ GroupName }}"
              $InstallDir = "C:\Temp\cb-install"

              Write-Host "==> Checking CarbonBlack CBC Sensor installation..."

              $CBProduct = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Carbon Black Cloud*" -or $_.Name -like "*CB Defense*" }
              $CurrentVersion = $CBProduct?.Version

              if ($CurrentVersion -and $CurrentVersion.StartsWith($TargetVersion)) {
                Write-Host "==> CarbonBlack $TargetVersion already installed."
                exit 0
              }

              Write-Host "==> Installing/upgrading CarbonBlack Sensor to $TargetVersion..."
              New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

              # Retrieve registration token from SSM Parameter Store (SecureString)
              try {
                $RegToken = (Get-SSMParameter -Name "/mandatory-apps/carbonblack/registration-token" -WithDecryption $true).Value
              } catch {
                Write-Host "==> WARNING: Could not retrieve CarbonBlack registration token from SSM."
                $RegToken = ""
              }

              $InstallerPath = Join-Path $InstallDir "cb-sensor.msi"
              Read-S3Object -BucketName "${var.s3_bucket_id}" -Key "windows/carbonblack/cb-psc-sensor-$TargetVersion.msi" -File $InstallerPath

              $MsiArgs = @(
                "/i", $InstallerPath,
                "/quiet",
                "/norestart",
                "REGISTRATION_TOKEN=$RegToken",
                "BACKEND_ADDR=$ServerUrl",
                "GROUP_NAME=$GroupName"
              )
              $Result = Start-Process msiexec.exe -ArgumentList $MsiArgs -Wait -PassThru
              if ($Result.ExitCode -notin @(0, 1641, 3010)) {
                throw "CarbonBlack installation failed with exit code $($Result.ExitCode)"
              }

              Write-Host "==> CarbonBlack $TargetVersion installation complete."
              Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
  YAML

  tags = merge(var.common_tags, { Application = "carbonblack-agent", OS = "windows" })
}

###############################################################################
# 3. SSM COMPLIANCE - Windows compliance check document
###############################################################################

resource "aws_ssm_document" "windows_compliance_check" {
  name            = "${var.environment}-windows-mandatory-apps-compliance"
  document_type   = "Command"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: "2.2"
    description: "Evaluate compliance for all mandatory applications on Windows and report to SSM Compliance"
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
      - action: aws:runPowerShellScript
        name: EvaluateMandatoryAppsCompliance
        inputs:
          runCommand:
            - |
              $Region = (Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/placement/region" -UseBasicParsing -TimeoutSec 3) 2>/dev/null
              if (-not $Region) { $Region = "ap-southeast-2" }
              $InstanceId = (Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/instance-id" -UseBasicParsing -TimeoutSec 3)
              $ComplianceType = "MandatoryApplications"
              $ExecutionTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
              $OverallStatus = 0

              function Put-ComplianceItem($AppName, $Status, $Detail) {
                $ExecSummary = @{ ExecutionTime = $ExecutionTime }
                $Item = @{
                  Id       = $AppName
                  Title    = $AppName
                  Severity = "CRITICAL"
                  Status   = $Status
                  Details  = @{ Comment = $Detail }
                }
                try {
                  Write-SSMComplianceItem `
                    -ResourceId $InstanceId `
                    -ResourceType ManagedInstance `
                    -ComplianceType $ComplianceType `
                    -ExecutionSummary $ExecSummary `
                    -Item $Item `
                    -Region $Region
                  Write-Host "==> Compliance: $AppName = $Status ($Detail)"
                } catch {
                  Write-Host "==> WARNING: Could not write compliance for $AppName : $_"
                }
              }

              # --- Splunk Universal Forwarder ---
              $TargetVer = "{{ SplunkVersion }}"
              $SplunkExe = "C:\Program Files\SplunkUniversalForwarder\bin\splunk.exe"
              if (Test-Path $SplunkExe) {
                try {
                  $out = & $SplunkExe version 2>&1
                  $CurrentVer = if ($out -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { "unknown" }
                } catch { $CurrentVer = "unknown" }
                if ($CurrentVer -eq $TargetVer) {
                  Put-ComplianceItem "SplunkUniversalForwarder" "COMPLIANT" "Version $CurrentVer matches $TargetVer"
                } else {
                  Put-ComplianceItem "SplunkUniversalForwarder" "NON_COMPLIANT" "Installed=$CurrentVer Expected=$TargetVer"
                  $OverallStatus++
                }
              } else {
                Put-ComplianceItem "SplunkUniversalForwarder" "NON_COMPLIANT" "Not installed. Target=$TargetVer"
                $OverallStatus++
              }

              # --- Qualys Cloud Agent ---
              $TargetVer = "{{ QualysVersion }}"
              $QualysProduct = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Qualys Cloud Agent*" }
              if ($QualysProduct) {
                $CurrentVer = $QualysProduct.Version
                if ($CurrentVer -eq $TargetVer) {
                  Put-ComplianceItem "QualysCloudAgent" "COMPLIANT" "Version $CurrentVer matches $TargetVer"
                } else {
                  Put-ComplianceItem "QualysCloudAgent" "NON_COMPLIANT" "Installed=$CurrentVer Expected=$TargetVer"
                  $OverallStatus++
                }
              } else {
                Put-ComplianceItem "QualysCloudAgent" "NON_COMPLIANT" "Not installed. Target=$TargetVer"
                $OverallStatus++
              }

              # --- CloudWatch Agent ---
              $TargetVer = "{{ CloudWatchVersion }}"
              $CWAExe = "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.exe"
              if (Test-Path $CWAExe) {
                $FileVer = (Get-Item $CWAExe).VersionInfo.FileVersion
                $CurrentVer = ($FileVer -split '\.')[0..2] -join '.'
                if ($CurrentVer -eq $TargetVer) {
                  Put-ComplianceItem "CloudWatchAgent" "COMPLIANT" "Version $CurrentVer matches $TargetVer"
                } else {
                  Put-ComplianceItem "CloudWatchAgent" "NON_COMPLIANT" "Installed=$CurrentVer Expected=$TargetVer"
                  $OverallStatus++
                }
              } else {
                Put-ComplianceItem "CloudWatchAgent" "NON_COMPLIANT" "Not installed. Target=$TargetVer"
                $OverallStatus++
              }

              # --- CarbonBlack CBC Sensor ---
              $TargetVer = "{{ CarbonBlackVersion }}"
              $CBProduct = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Carbon Black Cloud*" -or $_.Name -like "*CB Defense*" }
              if ($CBProduct) {
                $CurrentVer = $CBProduct.Version
                if ($CurrentVer.StartsWith($TargetVer)) {
                  Put-ComplianceItem "CarbonBlackCBCSensor" "COMPLIANT" "Version $CurrentVer matches $TargetVer"
                } else {
                  Put-ComplianceItem "CarbonBlackCBCSensor" "NON_COMPLIANT" "Installed=$CurrentVer Expected=$TargetVer"
                  $OverallStatus++
                }
              } else {
                Put-ComplianceItem "CarbonBlackCBCSensor" "NON_COMPLIANT" "Not installed. Target=$TargetVer"
                $OverallStatus++
              }

              Write-Host "==> Compliance check complete. Non-compliant items: $OverallStatus"
              exit 0
  YAML

  tags = merge(var.common_tags, { OS = "windows", Purpose = "compliance-reporting" })
}

###############################################################################
# 4. SSM INVENTORY - Windows inventory collection
###############################################################################

resource "aws_ssm_association" "windows_inventory" {
  name             = "AWS-GatherSoftwareInventory"
  association_name = "${var.environment}-windows-mandatory-apps-inventory"

  schedule_expression = "rate(30 minutes)"

  targets {
    key    = var.windows_target_key
    values = var.windows_target_values
  }

  parameters = {
    applications         = "Enabled"
    awsComponents        = "Enabled"
    customInventory      = "Enabled"
    instanceDetailedInfo = "Enabled"
    networkConfig        = "Disabled"
    services             = "Enabled"
    windowsRoles         = "Enabled"    # Windows-specific
  }

  sync_compliance = "AUTO"

  tags = merge(var.common_tags, { OS = "windows", Purpose = "inventory" })
}

###############################################################################
# 5. SSM STATE MANAGER - Windows enforcement associations
###############################################################################

resource "aws_ssm_association" "windows_install_splunk_uf" {
  name             = aws_ssm_document.windows_install_splunk_uf.name
  association_name = "${var.environment}-windows-enforce-splunk-uf"

  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false

  targets {
    key    = var.windows_target_key
    values = var.windows_target_values
  }

  parameters = {
    TargetVersion    = var.mandatory_app_versions["splunk_uf"]
    DeploymentServer = var.splunk_deployment_server
  }

  max_errors      = "10%"
  max_concurrency = "20%"
  compliance_severity = "CRITICAL"

  output_location {
    s3_bucket_name = var.s3_bucket_id
    s3_key_prefix  = "ssm-output/windows/splunk-uf"
  }

  tags = merge(var.common_tags, { Application = "splunk-uf", OS = "windows" })
}

resource "aws_ssm_association" "windows_install_qualys_agent" {
  name             = aws_ssm_document.windows_install_qualys_agent.name
  association_name = "${var.environment}-windows-enforce-qualys-agent"

  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false

  targets {
    key    = var.windows_target_key
    values = var.windows_target_values
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
    s3_key_prefix  = "ssm-output/windows/qualys-agent"
  }

  tags = merge(var.common_tags, { Application = "qualys-agent", OS = "windows" })
}

resource "aws_ssm_association" "windows_install_cloudwatch_agent" {
  name             = aws_ssm_document.windows_install_cloudwatch_agent.name
  association_name = "${var.environment}-windows-enforce-cloudwatch-agent"

  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false

  targets {
    key    = var.windows_target_key
    values = var.windows_target_values
  }

  parameters = {
    TargetVersion = var.mandatory_app_versions["cloudwatch"]
  }

  max_errors      = "10%"
  max_concurrency = "20%"
  compliance_severity = "CRITICAL"

  output_location {
    s3_bucket_name = var.s3_bucket_id
    s3_key_prefix  = "ssm-output/windows/cloudwatch-agent"
  }

  tags = merge(var.common_tags, { Application = "cloudwatch-agent", OS = "windows" })
}

resource "aws_ssm_association" "windows_install_carbonblack" {
  name             = aws_ssm_document.windows_install_carbonblack.name
  association_name = "${var.environment}-windows-enforce-carbonblack"

  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false

  targets {
    key    = var.windows_target_key
    values = var.windows_target_values
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
    s3_key_prefix  = "ssm-output/windows/carbonblack"
  }

  tags = merge(var.common_tags, { Application = "carbonblack-agent", OS = "windows" })
}

resource "aws_ssm_association" "windows_compliance_check" {
  name             = aws_ssm_document.windows_compliance_check.name
  association_name = "${var.environment}-windows-compliance-report"

  schedule_expression        = var.schedule_expression
  apply_only_at_cron_interval = false

  targets {
    key    = var.windows_target_key
    values = var.windows_target_values
  }

  parameters = {
    SplunkVersion      = var.mandatory_app_versions["splunk_uf"]
    QualysVersion      = var.mandatory_app_versions["qualys_agent"]
    CloudWatchVersion  = var.mandatory_app_versions["cloudwatch"]
    CarbonBlackVersion = var.mandatory_app_versions["carbonblack"]
  }

  max_errors      = "25%"
  max_concurrency = "50%"
  compliance_severity = "CRITICAL"

  output_location {
    s3_bucket_name = var.s3_bucket_id
    s3_key_prefix  = "ssm-output/windows/compliance"
  }

  tags = merge(var.common_tags, { OS = "windows", Purpose = "compliance" })
}
