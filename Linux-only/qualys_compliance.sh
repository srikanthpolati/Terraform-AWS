#!/usr/bin/env bash
# =============================================================================
# Qualys Cloud Agent - Compliance Check and Auto-Remediation (Linux)
# =============================================================================

set -euo pipefail

TARGET_VERSION="${QualysTargetVersion:-}"
S3_BUCKET="${S3Bucket:-}"
ACTIVATION_ID="${QualysActivationId:-}"
CUSTOMER_ID="${QualysCustomerId:-}"
AWS_REGION="${AWSRegion:-ap-southeast-2}"
ENVIRONMENT="${Environment:-unknown}"

QUALYS_INSTALL_PATH="/usr/local/qualys/cloud-agent"
COMPLIANCE_DIR="/tmp/ssm_compliance_results"
RESULT_FILE="$COMPLIANCE_DIR/qualys.env"
TEMP_DIR="/tmp/ssm_remediation/qualys"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')][${1:-INFO}] ${2}"; }

detect_pkg_manager() {
    command -v rpm &>/dev/null && echo "rpm" && return
    command -v dpkg &>/dev/null && echo "deb" && return
    echo "unknown"
}

get_installed_version() {
    local pkg_mgr
    pkg_mgr=$(detect_pkg_manager)
    case "$pkg_mgr" in
        rpm)  rpm -q qualys-cloud-agent --queryformat '%{VERSION}' 2>/dev/null || true ;;
        deb)  dpkg-query -W -f='${Version}' qualys-cloud-agent 2>/dev/null || true ;;
    esac
    # Fallback: check binary
    if [ -x "$QUALYS_INSTALL_PATH/bin/qualys-cloud-agent" ]; then
        "$QUALYS_INSTALL_PATH/bin/qualys-cloud-agent" --version 2>/dev/null | \
            grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true
    fi
}

version_gte() {
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -qx "$2"
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
log INFO "=== Qualys Cloud Agent Compliance Check ==="

mkdir -p "$COMPLIANCE_DIR"

if [ -z "$TARGET_VERSION" ] || [ "$TARGET_VERSION" = "latest" ]; then
    TARGET_VERSION=$(aws ssm get-parameter \
        --name "/mandatory-apps/linux/qualys/target_version" \
        --region "$AWS_REGION" \
        --query "Parameter.Value" \
        --output text 2>/dev/null) || log WARN "Could not retrieve version from Parameter Store."
fi

log INFO "Target Qualys version: $TARGET_VERSION"

INSTALLED_VERSION=$(get_installed_version | head -n1 | tr -d '[:space:]')
IS_COMPLIANT=false

if [ -n "$INSTALLED_VERSION" ]; then
    log INFO "Installed Qualys version: $INSTALLED_VERSION"
    if version_gte "$INSTALLED_VERSION" "$TARGET_VERSION"; then
        IS_COMPLIANT=true
        log INFO "COMPLIANT"
    else
        log WARN "NON-COMPLIANT: $INSTALLED_VERSION < $TARGET_VERSION"
    fi
else
    log WARN "NON-COMPLIANT: Qualys Cloud Agent NOT installed."
fi

cat > "$RESULT_FILE" <<EOF
APP_NAME=QualysCloudAgent
TARGET_VERSION=${TARGET_VERSION}
INSTALLED_VERSION=${INSTALLED_VERSION:-NOT_INSTALLED}
IS_COMPLIANT=${IS_COMPLIANT}
EOF

# --------------------------------------------------------------------------
# Remediation
# --------------------------------------------------------------------------
if [ "$IS_COMPLIANT" = "false" ]; then
    log INFO "Starting Qualys Agent remediation..."
    mkdir -p "$TEMP_DIR"

    ARCH=$(uname -m)
    PKG_MGR=$(detect_pkg_manager)

    case "$PKG_MGR" in
        rpm)
            INSTALLER="qualys-cloud-agent-${TARGET_VERSION}-${ARCH}.rpm"
            INSTALL_CMD="rpm -Uvh"
            ;;
        deb)
            INSTALLER="qualys-cloud-agent-${TARGET_VERSION}-${ARCH}.deb"
            INSTALL_CMD="dpkg -i"
            ;;
        *)
            log ERROR "Unsupported package manager for Qualys. Exiting."
            exit 1
            ;;
    esac

    S3_KEY="linux/qualys/${INSTALLER}"
    LOCAL_INSTALLER="$TEMP_DIR/$INSTALLER"

    log INFO "Downloading s3://$S3_BUCKET/$S3_KEY"
    aws s3 cp "s3://$S3_BUCKET/$S3_KEY" "$LOCAL_INSTALLER" --region "$AWS_REGION" || {
        log ERROR "S3 download failed."
        exit 1
    }

    # Stop existing agent if upgrading
    systemctl stop qualys-cloud-agent 2>/dev/null || true

    log INFO "Installing Qualys Cloud Agent..."
    $INSTALL_CMD "$LOCAL_INSTALLER"

    # Activate the agent
    log INFO "Activating Qualys Cloud Agent..."
    /usr/local/qualys/cloud-agent/bin/qualys-cloud-agent.sh ActivationId="$ACTIVATION_ID" CustomerId="$CUSTOMER_ID"

    # Enable and start service
    systemctl enable qualys-cloud-agent 2>/dev/null || true
    systemctl start qualys-cloud-agent 2>/dev/null || true

    sleep 15

    NEW_VERSION=$(get_installed_version | head -n1 | tr -d '[:space:]')
    if [ -n "$NEW_VERSION" ] && version_gte "$NEW_VERSION" "$TARGET_VERSION"; then
        log INFO "REMEDIATION SUCCESS: Qualys Agent v$NEW_VERSION installed."
        sed -i "s/IS_COMPLIANT=false/IS_COMPLIANT=true/" "$RESULT_FILE"
        sed -i "s/INSTALLED_VERSION=.*/INSTALLED_VERSION=${NEW_VERSION}/" "$RESULT_FILE"
    else
        log ERROR "REMEDIATION FAILED."
    fi

    rm -rf "$TEMP_DIR"
fi

log INFO "=== Qualys Compliance Check Complete ==="
