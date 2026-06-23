#!/usr/bin/env bash
# =============================================================================
# AWS CloudWatch Agent - Compliance Check (Linux)
# =============================================================================
# CWAgent installation is managed by the AWS-ConfigureAWSPackage association.
# This script verifies presence and service state, restarts if stopped,
# and writes compliance status for consolidated reporting.
# =============================================================================

set -euo pipefail

TARGET_VERSION="${CWAgentTargetVersion:-latest}"
AWS_REGION="${AWSRegion:-ap-southeast-2}"
ENVIRONMENT="${Environment:-unknown}"

COMPLIANCE_DIR="/tmp/ssm_compliance_results"
RESULT_FILE="$COMPLIANCE_DIR/cloudwatch.env"

CW_AGENT_CTL="/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl"
CW_AGENT_BIN="/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')][${1:-INFO}] ${2}"; }

get_installed_version() {
    if [ -x "$CW_AGENT_BIN" ]; then
        "$CW_AGENT_BIN" --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true
    fi
}

version_gte() {
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -qx "$2"
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
log INFO "=== AWS CloudWatch Agent Compliance Check ==="

mkdir -p "$COMPLIANCE_DIR"

log INFO "Target version: $TARGET_VERSION (installation managed by AWS-ConfigureAWSPackage)"

INSTALLED_VERSION=$(get_installed_version | tr -d '[:space:]')
IS_INSTALLED=false
SERVICE_STATUS="UNKNOWN"
IS_COMPLIANT=false

if [ -n "$INSTALLED_VERSION" ]; then
    IS_INSTALLED=true
    log INFO "Installed CloudWatch Agent version: $INSTALLED_VERSION"

    # Check service status
    if systemctl is-active --quiet amazon-cloudwatch-agent 2>/dev/null; then
        SERVICE_STATUS="RUNNING"
        log INFO "Service status: RUNNING"
    else
        SERVICE_STATUS="STOPPED"
        log WARN "Service status: STOPPED — attempting restart..."

        # Attempt to restart
        if [ -x "$CW_AGENT_CTL" ]; then
            "$CW_AGENT_CTL" -a start 2>/dev/null || true
        else
            systemctl start amazon-cloudwatch-agent 2>/dev/null || true
        fi

        sleep 5
        if systemctl is-active --quiet amazon-cloudwatch-agent 2>/dev/null; then
            SERVICE_STATUS="RUNNING"
            log INFO "Service restarted successfully."
        else
            log ERROR "Failed to restart CloudWatch Agent service."
        fi
    fi

    # Version check (skip if target is 'latest' — AWS manages it)
    VERSION_OK=true
    if [ "$TARGET_VERSION" != "latest" ]; then
        version_gte "$INSTALLED_VERSION" "$TARGET_VERSION" && VERSION_OK=true || VERSION_OK=false
        if [ "$VERSION_OK" = "false" ]; then
            log WARN "NON-COMPLIANT: Version $INSTALLED_VERSION below target $TARGET_VERSION"
            log WARN "Version remediation is handled by the AWS-ConfigureAWSPackage State Manager association."
        fi
    fi

    [ "$SERVICE_STATUS" = "RUNNING" ] && [ "$VERSION_OK" = "true" ] && IS_COMPLIANT=true
else
    log WARN "NON-COMPLIANT: CloudWatch Agent NOT installed."
    log WARN "Installation will be triggered by the AWS-ConfigureAWSPackage State Manager association."
fi

cat > "$RESULT_FILE" <<EOF
APP_NAME=AmazonCloudWatchAgent
TARGET_VERSION=${TARGET_VERSION}
INSTALLED_VERSION=${INSTALLED_VERSION:-NOT_INSTALLED}
SERVICE_STATUS=${SERVICE_STATUS}
IS_COMPLIANT=${IS_COMPLIANT}
EOF

log INFO "=== CloudWatch Agent Compliance Check Complete ==="
