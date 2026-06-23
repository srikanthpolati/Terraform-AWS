#!/usr/bin/env bash
# =============================================================================
# CarbonBlack Agent - Compliance Check and Auto-Remediation (Linux)
# =============================================================================

set -euo pipefail

TARGET_VERSION="${CarbonBlackTargetVersion:-}"
S3_BUCKET="${S3Bucket:-}"
SERVER_URL="${CarbonBlackServerUrl:-}"
GROUP_NAME="${CarbonBlackGroupName:-default}"
AWS_REGION="${AWSRegion:-ap-southeast-2}"
ENVIRONMENT="${Environment:-unknown}"

COMPLIANCE_DIR="/tmp/ssm_compliance_results"
RESULT_FILE="$COMPLIANCE_DIR/carbonblack.env"
TEMP_DIR="/tmp/ssm_remediation/carbonblack"

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
        rpm)  rpm -q cb-psc-sensor --queryformat '%{VERSION}' 2>/dev/null || \
              rpm -q cb-sensor --queryformat '%{VERSION}' 2>/dev/null || true ;;
        deb)  dpkg-query -W -f='${Version}' cb-psc-sensor 2>/dev/null || \
              dpkg-query -W -f='${Version}' cb-sensor 2>/dev/null || true ;;
    esac
}

version_gte() {
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -qx "$2"
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
log INFO "=== CarbonBlack Agent Compliance Check ==="

mkdir -p "$COMPLIANCE_DIR"

if [ -z "$TARGET_VERSION" ] || [ "$TARGET_VERSION" = "latest" ]; then
    TARGET_VERSION=$(aws ssm get-parameter \
        --name "/mandatory-apps/linux/carbonblack/target_version" \
        --region "$AWS_REGION" \
        --query "Parameter.Value" \
        --output text 2>/dev/null) || log WARN "Could not retrieve version from Parameter Store."
fi

log INFO "Target CarbonBlack version: $TARGET_VERSION"

INSTALLED_VERSION=$(get_installed_version | head -n1 | tr -d '[:space:]')
IS_COMPLIANT=false

if [ -n "$INSTALLED_VERSION" ]; then
    log INFO "Installed CarbonBlack version: $INSTALLED_VERSION"
    if version_gte "$INSTALLED_VERSION" "$TARGET_VERSION"; then
        IS_COMPLIANT=true
        log INFO "COMPLIANT"
    else
        log WARN "NON-COMPLIANT: $INSTALLED_VERSION < $TARGET_VERSION"
    fi
else
    log WARN "NON-COMPLIANT: CarbonBlack Agent NOT installed."
fi

cat > "$RESULT_FILE" <<EOF
APP_NAME=CarbonBlackAgent
TARGET_VERSION=${TARGET_VERSION}
INSTALLED_VERSION=${INSTALLED_VERSION:-NOT_INSTALLED}
IS_COMPLIANT=${IS_COMPLIANT}
EOF

# --------------------------------------------------------------------------
# Remediation
# --------------------------------------------------------------------------
if [ "$IS_COMPLIANT" = "false" ]; then
    log INFO "Starting CarbonBlack Agent remediation..."
    mkdir -p "$TEMP_DIR"

    ARCH=$(uname -m)
    PKG_MGR=$(detect_pkg_manager)

    case "$PKG_MGR" in
        rpm)
            INSTALLER="cb-psc-sensor-${TARGET_VERSION}-${ARCH}.rpm"
            INSTALL_CMD="rpm -Uvh"
            ;;
        deb)
            INSTALLER="cb-psc-sensor-${TARGET_VERSION}-${ARCH}.deb"
            INSTALL_CMD="dpkg -i"
            ;;
        *)
            log ERROR "Unsupported package manager."
            exit 1
            ;;
    esac

    S3_KEY="linux/carbonblack/${INSTALLER}"
    LOCAL_INSTALLER="$TEMP_DIR/$INSTALLER"

    log INFO "Downloading s3://$S3_BUCKET/$S3_KEY"
    aws s3 cp "s3://$S3_BUCKET/$S3_KEY" "$LOCAL_INSTALLER" --region "$AWS_REGION" || {
        log ERROR "S3 download failed."
        exit 1
    }

    # Retrieve company registration code from Parameter Store (sensitive)
    COMPANY_CODE=$(aws ssm get-parameter \
        --name "/mandatory-apps/linux/carbonblack/company_code" \
        --region "$AWS_REGION" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text 2>/dev/null) || {
        log ERROR "Failed to retrieve CarbonBlack company code from Parameter Store."
        exit 1
    }

    # Stop existing sensor
    systemctl stop cbagentd 2>/dev/null || true

    log INFO "Installing CarbonBlack Agent..."
    $INSTALL_CMD "$LOCAL_INSTALLER"

    # Register sensor
    log INFO "Registering CarbonBlack sensor..."
    /usr/share/cb/psc/cbagentd -a "$COMPANY_CODE" 2>/dev/null || \
    /opt/carbonblack/psc/cbagentd --register "$COMPANY_CODE" 2>/dev/null || true

    systemctl enable cbagentd 2>/dev/null || true
    systemctl start cbagentd 2>/dev/null || true

    sleep 20

    NEW_VERSION=$(get_installed_version | head -n1 | tr -d '[:space:]')
    if [ -n "$NEW_VERSION" ] && version_gte "$NEW_VERSION" "$TARGET_VERSION"; then
        log INFO "REMEDIATION SUCCESS: CarbonBlack v$NEW_VERSION installed."
        sed -i "s/IS_COMPLIANT=false/IS_COMPLIANT=true/" "$RESULT_FILE"
        sed -i "s/INSTALLED_VERSION=.*/INSTALLED_VERSION=${NEW_VERSION}/" "$RESULT_FILE"
    else
        log ERROR "REMEDIATION FAILED."
    fi

    rm -rf "$TEMP_DIR"
fi

log INFO "=== CarbonBlack Compliance Check Complete ==="
