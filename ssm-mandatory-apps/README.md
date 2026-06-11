# SSM Mandatory Application Management — Terraform

Manages deployment, enforcement, and compliance monitoring of four mandatory agents
across Linux and Windows EC2 instances using AWS Systems Manager.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    SSM COMPONENT FLOW                           │
│                                                                 │
│  SSM Parameter Store ──► target versions (single source)       │
│         │                                                       │
│         ▼                                                       │
│  State Manager ──► runs Command documents on schedule          │
│         │          AND at instance registration                 │
│         ▼                                                       │
│  Command Document ──► checks installed version                  │
│         │              if wrong → pulls from S3 via Distributor │
│         ▼                                                       │
│  S3 Packages (Distributor) ──► installs/upgrades agent         │
│         │                                                       │
│         ▼                                                       │
│  Compliance Document ──► put-compliance-items per agent        │
│         │                                                       │
│         ▼                                                       │
│  SSM Compliance Dashboard ──► COMPLIANT / NON_COMPLIANT        │
│                                                                 │
│  SSM Inventory (parallel) ──► installed software metadata      │
└─────────────────────────────────────────────────────────────────┘
```

## What gets deployed

| Component | Resource | Purpose |
|---|---|---|
| **SSM Distributor** | `aws_ssm_document` (Package type) | Defines versioned package with S3 pointers |
| **SSM State Manager** | `aws_ssm_association` | Enforces installation on schedule + startup |
| **SSM Inventory** | `aws_ssm_association` (AWS-GatherSoftwareInventory) | Collects installed app metadata |
| **SSM Compliance** | `aws_ssm_document` + `aws_ssm_association` | Reports per-app COMPLIANT/NON_COMPLIANT |
| **S3 Bucket** | `aws_s3_bucket` | Stores install packages and association output logs |
| **IAM Role/Profile** | `aws_iam_role`, `aws_iam_instance_profile` | Grants EC2 permission to use SSM and read S3 |
| **SSM Parameters** | `aws_ssm_parameter` | Version config — single source of truth |

## Modules

```
ssm-mandatory-apps/
├── main.tf                          # Root: S3, IAM, SSM Parameters, module calls
├── variables.tf                     # Root variables
├── outputs.tf                       # Root outputs
├── terraform.tfvars.example         # Copy → terraform.tfvars and populate
└── modules/
    ├── ssm-linux/
    │   ├── main.tf                  # Linux: Distributor docs, install docs, compliance, inventory, associations
    │   ├── variables.tf
    │   └── outputs.tf
    └── ssm-windows/
        ├── main.tf                  # Windows: same structure with PowerShell scripts
        ├── variables.tf
        └── outputs.tf
```

---

## Prerequisites

### 1. EC2 Instance Requirements

All managed instances must have:
- **SSM Agent** installed and running (pre-installed on Amazon Linux 2, Windows Server 2016+)
- The IAM instance profile output by this module attached: `ec2_instance_profile_name`
- Network access to SSM endpoints (via internet gateway, NAT, or VPC endpoints)

```bash
# Verify SSM agent is running — Linux
sudo systemctl status amazon-ssm-agent

# Verify SSM agent is running — Windows
Get-Service AmazonSSMAgent
```

### 2. EC2 Instance Tagging

Instances are targeted by tag. Apply these tags to all EC2 instances:

```
OS = Linux          # or: AmazonLinux, RHEL, Ubuntu
OS = Windows
```

You can change the tag key/value in `terraform.tfvars` via `linux_target_key`,
`linux_target_values`, `windows_target_key`, `windows_target_values`.

### 3. Upload Installation Packages to S3

After `terraform apply`, upload your agent installers to the S3 bucket. The bucket
name is shown in the `s3_package_bucket` output.

**Required S3 key structure:**
```
linux/
  splunk-uf/
    splunkforwarder-<VERSION>-x86_64.rpm
    splunkforwarder-<VERSION>-x86_64.deb
    splunkforwarder-<VERSION>-arm64.rpm     (optional, for Graviton)
  qualys-agent/
    qualys-cloud-agent-<VERSION>.rpm
    qualys-cloud-agent-<VERSION>.deb
  cloudwatch-agent/
    amazon-cloudwatch-agent-linux-<VERSION>.zip
  carbonblack/
    cb-psc-sensor-<VERSION>.rpm
    cb-psc-sensor_<VERSION>.deb

windows/
  splunk-uf/
    splunkforwarder-<VERSION>-x64-release.msi
  qualys-agent/
    QualysCloudAgent-<VERSION>.exe
  cloudwatch-agent/
    amazon-cloudwatch-agent-<VERSION>.msi
  carbonblack/
    cb-psc-sensor-<VERSION>.msi
```

**After uploading, update the SHA256 checksums** in the Distributor package documents:
```hcl
# In modules/ssm-linux/main.tf and modules/ssm-windows/main.tf
# Replace: "REPLACE_WITH_ACTUAL_SHA256_AFTER_UPLOADING_PACKAGE"
# With the actual SHA256 of each uploaded zip/msi/rpm
```

### 4. SSM Parameter Store — Secrets

Store sensitive values that the scripts reference at runtime:

```bash
# CarbonBlack registration token (SecureString)
aws ssm put-parameter \
  --name "/mandatory-apps/carbonblack/registration-token" \
  --type "SecureString" \
  --value "<YOUR_CBC_REGISTRATION_TOKEN>"

# Optional: CloudWatch Agent config JSON (Linux)
aws ssm put-parameter \
  --name "/mandatory-apps/cloudwatch-agent-config/linux" \
  --type "String" \
  --value "$(cat cloudwatch-agent-linux.json)"

# Optional: CloudWatch Agent config JSON (Windows)
aws ssm put-parameter \
  --name "/mandatory-apps/cloudwatch-agent-config/windows" \
  --type "String" \
  --value "$(cat cloudwatch-agent-windows.json)"
```

---

## Deployment

```bash
# 1. Copy and populate variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Initialise
terraform init

# 3. Review
terraform plan

# 4. Apply
terraform apply
```

---

## Updating Application Versions

To roll out a new version across your entire EC2 estate:

```hcl
# terraform.tfvars — bump version number(s)
mandatory_app_versions = {
  splunk_uf    = "9.4.0"   # ← updated
  qualys_agent = "4.7.0"
  cloudwatch   = "3.3.0"
  carbonblack  = "3.9.1"
}
```

Then:
1. Upload the new package to S3 under the appropriate key
2. Update the SHA256 checksum in the Distributor document
3. `terraform apply` — pushes new version to SSM Parameter Store and updates the Distributor document
4. State Manager will enforce the new version on next scheduled run (or immediately on new instances)

---

## Viewing Compliance Results

### AWS Console
**Systems Manager → Compliance**
- Filter by **Compliance type**: `MandatoryApplications`
- Each instance shows COMPLIANT/NON_COMPLIANT per application
- Drill in for exact installed vs expected version

### AWS CLI
```bash
# Summary across all instances
aws ssm list-compliance-summaries \
  --filters "Key=ComplianceType,Values=MandatoryApplications"

# Non-compliant instances
aws ssm list-resource-compliance-summaries \
  --filters "Key=ComplianceType,Values=MandatoryApplications,Type=EQUAL" \
             "Key=OverallSeverity,Values=CRITICAL,Type=EQUAL" \
             "Key=Status,Values=NON_COMPLIANT,Type=EQUAL"

# Specific instance detail
aws ssm list-compliance-items \
  --resource-ids i-0abc1234def56789 \
  --resource-types ManagedInstance \
  --filters "Key=ComplianceType,Values=MandatoryApplications"
```

### Viewing Inventory
```bash
# List installed software on an instance
aws ssm list-inventory-entries \
  --instance-id i-0abc1234def56789 \
  --type-name AWS:Application
```

---

## Association Execution Logs

All State Manager association outputs are written to S3:
```
s3://<bucket>/ssm-output/linux/splunk-uf/<instance-id>/<execution-id>/stdout
s3://<bucket>/ssm-output/linux/splunk-uf/<instance-id>/<execution-id>/stderr
```

---

## Behaviour on Non-Compliant Instance

When State Manager runs and finds a missing or wrong-version agent:

1. **Detection**: script checks installed version vs `TargetVersion` parameter
2. **Remediation**: downloads package from S3 and installs/upgrades silently
3. **Service restart**: ensures the service is running post-install
4. **Compliance update**: separate compliance association writes `COMPLIANT` to SSM Compliance
5. **Logging**: stdout/stderr captured to S3 for audit trail

New instances (at registration): `apply_only_at_cron_interval = false` ensures the
association runs immediately when an instance registers with SSM — no window of exposure.

---

## IAM Requirements for Pipeline / Deployment Role

The role running `terraform apply` needs:
```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:CreateDocument", "ssm:UpdateDocument", "ssm:DeleteDocument",
    "ssm:CreateAssociation", "ssm:UpdateAssociation", "ssm:DeleteAssociation",
    "ssm:PutParameter", "ssm:GetParameter", "ssm:DeleteParameter",
    "s3:CreateBucket", "s3:PutObject", "s3:GetObject",
    "iam:CreateRole", "iam:AttachRolePolicy", "iam:CreateInstanceProfile",
    "iam:PassRole"
  ],
  "Resource": "*"
}
```
