#!/usr/bin/env bash
# =============================================================================
# Operator Runbook — Linux Mandatory App Installer
# =============================================================================
# Run this script to install mandatory applications on one or more NEW Linux
# EC2 instances. It triggers SSM Run Command targeting only the instances
# you specify — it will NEVER run on instances you don't explicitly pass in.
#
# The underlying scripts are idempotent: if an app is already installed at
# the correct version, it is detected as COMPLIANT and skipped — no reinstall.
#
# Usage:
#   ./run_mandatory_apps.sh --instance-id i-0abc123def456
#   ./run_mandatory_apps.sh --instance-ids i-0abc,i-0def,i-0ghi
#   ./run_mandatory_apps.sh --tag-key NewBuild --tag-value true
#   ./run_mandatory_apps.sh --instance-id i-0abc123 --no-wait
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------
# Defaults (override via flags or environment variables)
# --------------------------------------------------------------------------
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
ENVIRONMENT="${TF_VAR_environment:-prod}"
INSTANCE_ID=""
INSTANCE_IDS=""
TAG_KEY=""
TAG_VALUE=""
WAIT=true
TIMEOUT=1800

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Target (one required):
  --instance-id  <id>         Single instance ID (e.g. i-0abc123def456)
  --instance-ids <id,id,...>  Comma-separated list of instance IDs
  --tag-key      <key>        Target by EC2 tag key (use with --tag-value)
  --tag-value    <value>      Target by EC2 tag value (use with --tag-key)

Options:
  --region       <region>     AWS region (default: $AWS_REGION)
  --environment  <env>        Environment name (default: $ENVIRONMENT)
  --no-wait                   Fire and forget — don't poll for completion
  --help                      Show this message

Examples:
  # Install on a single new instance
  $0 --instance-id i-0abc123def456

  # Install on several new instances at once
  $0 --instance-ids i-0abc123,i-0def456,i-0ghi789

  # Install on all instances tagged NewBuild=true
  $0 --tag-key NewBuild --tag-value true
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance-id)  INSTANCE_ID="$2";  shift 2 ;;
    --instance-ids) INSTANCE_IDS="$2"; shift 2 ;;
    --tag-key)      TAG_KEY="$2";      shift 2 ;;
    --tag-value)    TAG_VALUE="$2";    shift 2 ;;
    --region)       AWS_REGION="$2";   shift 2 ;;
    --environment)  ENVIRONMENT="$2";  shift 2 ;;
    --no-wait)      WAIT=false;        shift ;;
    --help|-h)      usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# --------------------------------------------------------------------------
# Validate
# --------------------------------------------------------------------------
if [[ -z "$INSTANCE_ID" && -z "$INSTANCE_IDS" && ( -z "$TAG_KEY" || -z "$TAG_VALUE" ) ]]; then
  echo "ERROR: Provide --instance-id, --instance-ids, or --tag-key + --tag-value"
  exit 1
fi

# --------------------------------------------------------------------------
# Resolve SSM document name from Terraform output
# --------------------------------------------------------------------------
echo "==> Resolving SSM document name from Terraform output..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DOCUMENT_NAME=$(terraform -chdir="$SCRIPT_DIR" output -raw run_command_document_name 2>/dev/null) || true

if [[ -z "$DOCUMENT_NAME" ]]; then
  DOCUMENT_NAME="MandatoryApp-ComplianceInstall-Linux-${ENVIRONMENT}"
  echo "    Terraform output unavailable — using convention: $DOCUMENT_NAME"
else
  echo "    Document: $DOCUMENT_NAME"
fi

# --------------------------------------------------------------------------
# Build targets JSON
# --------------------------------------------------------------------------
if [[ -n "$INSTANCE_ID" ]]; then
  TARGETS_JSON="[{\"Key\":\"InstanceIds\",\"Values\":[\"$INSTANCE_ID\"]}]"
elif [[ -n "$INSTANCE_IDS" ]]; then
  IDS_JSON=$(echo "$INSTANCE_IDS" | sed 's/,/","/g; s/^/"/; s/$/"/')
  TARGETS_JSON="[{\"Key\":\"InstanceIds\",\"Values\":[$IDS_JSON]}]"
else
  TARGETS_JSON="[{\"Key\":\"tag:$TAG_KEY\",\"Values\":[\"$TAG_VALUE\"]}]"
fi

# --------------------------------------------------------------------------
# Confirmation prompt
# --------------------------------------------------------------------------
S3_BUCKET=$(terraform -chdir="$SCRIPT_DIR" output -raw s3_bucket_name 2>/dev/null) || S3_BUCKET=""

echo ""
echo "============================================================"
echo "  Linux Mandatory App Installation"
echo "============================================================"
echo "  Document    : $DOCUMENT_NAME"
echo "  Targets     : $TARGETS_JSON"
echo "  Region      : $AWS_REGION"
echo "  Environment : $ENVIRONMENT"
echo "============================================================"
echo ""
read -r -p "Proceed? (yes/no): " CONFIRM
[[ "$CONFIRM" != "yes" ]] && { echo "Aborted."; exit 0; }

# --------------------------------------------------------------------------
# Send Run Command
# --------------------------------------------------------------------------
echo ""
echo "==> Sending SSM Run Command..."

S3_ARGS=()
[[ -n "$S3_BUCKET" ]] && S3_ARGS=(
  "--output-s3-bucket-name" "$S3_BUCKET"
  "--output-s3-key-prefix"  "ssm-output/linux/manual-runs"
)

COMMAND_ID=$(aws ssm send-command \
  --document-name   "$DOCUMENT_NAME" \
  --targets         "$TARGETS_JSON" \
  --region          "$AWS_REGION" \
  --comment         "Mandatory app install — $(whoami) at $(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --timeout-seconds "$TIMEOUT" \
  "${S3_ARGS[@]}" \
  --query  "Command.CommandId" \
  --output text)

echo "    Command ID  : $COMMAND_ID"
echo "    Console URL : https://${AWS_REGION}.console.aws.amazon.com/systems-manager/run-command/${COMMAND_ID}"
echo ""

# --------------------------------------------------------------------------
# Optionally wait and report
# --------------------------------------------------------------------------
if [[ "$WAIT" == "true" ]]; then
  echo "==> Waiting for completion (Ctrl+C to stop waiting — command continues running)..."
  echo ""
  START=$(date +%s)

  while true; do
    sleep 15
    STATUS=$(aws ssm list-commands \
      --command-id "$COMMAND_ID" \
      --region     "$AWS_REGION" \
      --query      "Commands[0].StatusDetails" \
      --output     text 2>/dev/null)

    ELAPSED=$(( $(date +%s) - START ))
    echo "    [${ELAPSED}s] $STATUS"

    case "$STATUS" in
      Success)
        echo ""
        echo "==> All targets completed successfully."
        break ;;
      Failed|Cancelled|TimedOut|DeliveryTimedOut|ExecutionTimedOut)
        echo ""
        echo "==> Command ended with status: $STATUS"
        echo "    Review per-instance output below and in SSM Compliance."
        aws ssm list-command-invocations \
          --command-id "$COMMAND_ID" \
          --region     "$AWS_REGION" \
          --details \
          --query      "CommandInvocations[*].{Instance:InstanceId,Status:StatusDetails}" \
          --output     table
        exit 1 ;;
    esac

    [[ $(( $(date +%s) - START )) -gt $TIMEOUT ]] && {
      echo "==> Local wait timed out. Check the console for status."
      exit 1
    }
  done

  echo ""
  echo "==> Per-instance results:"
  aws ssm list-command-invocations \
    --command-id "$COMMAND_ID" \
    --region     "$AWS_REGION" \
    --details \
    --query      "CommandInvocations[*].{Instance:InstanceId,Status:StatusDetails}" \
    --output     table

  echo ""
  echo "==> SSM Compliance (results visible within ~2 minutes):"
  echo "    https://${AWS_REGION}.console.aws.amazon.com/systems-manager/compliance"
else
  echo "==> Running in background. Monitor at:"
  echo "    https://${AWS_REGION}.console.aws.amazon.com/systems-manager/run-command/${COMMAND_ID}"
fi
