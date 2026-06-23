#!/usr/bin/env bash
# =============================================================================
# Splunk Universal Forwarder - Compliance Check and Auto-Remediation (Linux)
# =============================================================================
# Called by SSM State Manager on schedule.
# 1. Reads target version from Parameter Store or SSM document parameter
# 2. Detects installed version via package manager or binary
# 3. Writes result to shared state file for consolidation
# 4. Downloads from S3 and installs if non-compliant
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------
# Configuration (injected by SSM document or set from environment)
# --------------------------------------------------------------------------
TARGET_VERSION="${SplunkTargetVersion:-}"
S3_BUCKET="${S3Bucket:-}"
DEPLOYMENT_SERVER="${SplunkDeploymentServer:-}"
INDEX_NAME="${SplunkIndexName:-main}"
AWS_REGION="${AWSRegion:-ap-southeast-2}"
ENVIRONMENT="${Environment:-unknown}"

SPLUNK_HOME="/opt/splunkforwarder"
COMPLIANCE_DIR="/tmp/ssm_compliance_results"
RESULT_FILE="$COMPLIANCE_DIR/splunk.env"
TEMP_DIR="/tmp/ssm_remediation/splunk"

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')][${1:-INFO}] ${2}"; }

# --------------------------------------------------------------------------
# Detect Linux distribution and package manager
# --------------------------------------------------------------------------
detect_pkg_manager() {
    if command -v rpm &>/dev/null && [ -f /etc/redhat-release ]; then
        echo "rpm"
    elif command -v dpkg &>/dev/null && [ -f /etc/debian_version ]; then
        echo "deb"
    else
        echo "unknown"
    fi
}

# --------------------------------------------------------------------------
# Get installed Splunk version
# --------------------------------------------------------------------------
get_installed_version() {
    local pkg_mgr
    pkg_mgr=$(detect_pkg_manager)

    # Try package manager first
    case "$pkg_mgr" in
        rpm)
            rpm -q SplunkUniversalForwarder --queryformat '%{VERSION}' 2>/dev/null || true
            ;;
        deb)
            dpkg-query -W -f='${Version}' splunkforwarder 2>/dev/null || true
            ;;
    esac

    # Fallback: try binary
    if [ -x "$SPLUNK_HOME/bin/splunk" ]; then
        "$SPLUNK_HOME/bin/splunk" version --accept-license 2>/dev/null | \
            grep -oP 'Splunk Universal Forwarder \K[0-9]+\.[0-9]+\.[0-9]+' || true
    fi
}

# --------------------------------------------------------------------------
# Version comparison (semver)
# --------------------------------------------------------------------------
version_gte() {
    # Returns 0 (true) if $1 >= $2
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -qx "$2"
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
log INFO "=== Splunk Universal Forwarder Compliance Check ==="

mkdir -p "$COMPLIANCE_DIR"

# Resolve target version from Parameter Store if not set or 'latest'
if [ -z "$TARGET_VERSION" ] || [ "$TARGET_VERSION" = "latest" ]; then
    log INFO "Resolving target version from SSM Parameter Store..."
    TARGET_VERSION=$(aws ssm get-parameter \
        --name "/mandatory-apps/linux/splunk/target_version" \
        --region "$AWS_REGION" \
        --query "Parameter.Value" \
        --output text 2>/dev/null) || {
        log WARN "Could not retrieve version from Parameter Store."
    }
fi

log INFO "Target Splunk UF version: $TARGET_VERSION"

# Check installed version
INSTALLED_VERSION=$(get_installed_version | head -n1 | tr -d '[:space:]')
IS_INSTALLED=false
IS_COMPLIANT=false

if [ -n "$INSTALLED_VERSION" ]; then
    IS_INSTALLED=true
    log INFO "Installed Splunk UF version: $INSTALLED_VERSION"
    if version_gte "$INSTALLED_VERSION" "$TARGET_VERSION"; then
        IS_COMPLIANT=true
        log INFO "COMPLIANT: Installed version meets target."
    else
        log WARN "NON-COMPLIANT: $INSTALLED_VERSION < $TARGET_VERSION"
    fi
else
    log WARN "NON-COMPLIANT: Splunk Universal Forwarder NOT installed."
fi

# Write result for consolidation step
cat > "$RESULT_FILE" <<EOF
APP_NAME=SplunkUniversalForwarder
TARGET_VERSION=${TARGET_VERSION}
INSTALLED_VERSION=${INSTALLED_VERSION:-NOT_INSTALLED}
IS_COMPLIANT=${IS_COMPLIANT}
EOF

# --------------------------------------------------------------------------
# Remediation
# --------------------------------------------------------------------------
if [ "$IS_COMPLIANT" = "false" ]; then
    log INFO "Starting Splunk UF remediation..."
    mkdir -p "$TEMP_DIR"

    ARCH=$(uname -m)
    PKG_MGR=$(detect_pkg_manager)

    case "$PKG_MGR" in
        rpm)
            INSTALLER="splunkforwarder-${TARGET_VERSION}-linux-${ARCH}.rpm"
            INSTALL_CMD="rpm -Uvh"
            ;;
        deb)
            INSTALLER="splunkforwarder-${TARGET_VERSION}-linux-${ARCH}.deb"
            INSTALL_CMD="dpkg -i"
            ;;
        *)
            INSTALLER="splunkforwarder-${TARGET_VERSION}-Linux-${ARCH}.tgz"
            INSTALL_CMD="tar"
            ;;
    esac

    S3_KEY="linux/splunk/${INSTALLER}"
    LOCAL_INSTALLER="$TEMP_DIR/$INSTALLER"

    log INFO "Downloading s3://$S3_BUCKET/$S3_KEY"
    aws s3 cp "s3://$S3_BUCKET/$S3_KEY" "$LOCAL_INSTALLER" --region "$AWS_REGION" || {
        log ERROR "S3 download failed. Aborting remediation."
        exit 1
    }

    # Stop existing Splunk if running
    if systemctl is-active --quiet SplunkForwarder 2>/dev/null; then
        log INFO "Stopping SplunkForwarder service for upgrade..."
        "$SPLUNK_HOME/bin/splunk" stop || true
    fi

    # Install
    case "$PKG_MGR" in
        rpm|deb)
            log INFO "Installing via $INSTALL_CMD..."
            $INSTALL_CMD "$LOCAL_INSTALLER"
            ;;
        *)
            log INFO "Installing via tarball..."
            tar -xzf "$LOCAL_INSTALLER" -C /opt/
            ;;
    esac

    # Accept license and configure
    "$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt \
        --seed-passwd changeme || true

    # Configure deployment server
    if [ -n "$DEPLOYMENT_SERVER" ]; then
        "$SPLUNK_HOME/bin/splunk" set deploy-poll "$DEPLOYMENT_SERVER" \
            -auth admin:changeme || true
    fi

    # Enable as service
    "$SPLUNK_HOME/bin/splunk" enable boot-start -systemd-managed 1 \
        --accept-license --answer-yes 2>/dev/null || \
    "$SPLUNK_HOME/bin/splunk" enable boot-start --accept-license --answer-yes || true

    # Start service
    systemctl start SplunkForwarder 2>/dev/null || \
        "$SPLUNK_HOME/bin/splunk" start || true

    sleep 10

    # Verify
    NEW_VERSION=$(get_installed_version | head -n1 | tr -d '[:space:]')
    if [ -n "$NEW_VERSION" ] && version_gte "$NEW_VERSION" "$TARGET_VERSION"; then
        log INFO "REMEDIATION SUCCESS: Splunk UF v$NEW_VERSION installed."
        sed -i "s/IS_COMPLIANT=false/IS_COMPLIANT=true/" "$RESULT_FILE"
        sed -i "s/INSTALLED_VERSION=.*/INSTALLED_VERSION=${NEW_VERSION}/" "$RESULT_FILE"
    else
        log ERROR "REMEDIATION FAILED: Post-install version check failed."
    fi

    rm -rf "$TEMP_DIR"
fi

log INFO "=== Splunk UF Compliance Check Complete ==="
