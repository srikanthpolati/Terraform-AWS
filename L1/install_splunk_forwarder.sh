#!/bin/bash
# =============================================================================
# Splunk Universal Forwarder - Installation Script (Linux)
# Executed via AWS SSM Run Command / SSM Document
# Package source: S3 (no internet download)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Variables injected by SSM document parameters (via templatefile() in TF)
# ---------------------------------------------------------------------------
S3_BUCKET="${s3_bucket}"
S3_KEY="${s3_key}"
SPLUNK_INSTALL_DIR="${splunk_install_dir}"
SPLUNK_USER="${splunk_user}"
SPLUNK_GROUP="${splunk_group}"
SPLUNK_DEPLOYMENT_SERVER="${deployment_server}"
SPLUNK_DEPLOYMENT_PORT="${deployment_server_port}"
SPLUNK_ADMIN_PASSWORD="${splunk_admin_password}"
AWS_REGION="${aws_region}"

PACKAGE_FILENAME=$(basename "$S3_KEY")
TMP_DIR="/tmp/splunk-install"
LOG_FILE="/var/log/splunk-forwarder-install.log"

# ---------------------------------------------------------------------------
# Logging helper
# ---------------------------------------------------------------------------
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
log "Starting Splunk Universal Forwarder installation"
log "S3 Source: s3://$S3_BUCKET/$S3_KEY"
log "Install directory: $SPLUNK_INSTALL_DIR"

# Detect OS family
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="$ID"
  OS_VERSION="$VERSION_ID"
else
  log "ERROR: Cannot detect OS. /etc/os-release not found."
  exit 1
fi

log "Detected OS: $OS_ID $OS_VERSION"

# Abort if Splunk forwarder is already installed
if [ -d "$SPLUNK_INSTALL_DIR/splunkforwarder" ]; then
  log "Splunk Universal Forwarder already exists at $SPLUNK_INSTALL_DIR/splunkforwarder. Exiting."
  exit 0
fi

# ---------------------------------------------------------------------------
# Create splunk user/group if not present
# ---------------------------------------------------------------------------
if ! getent group "$SPLUNK_GROUP" > /dev/null 2>&1; then
  log "Creating group: $SPLUNK_GROUP"
  groupadd --system "$SPLUNK_GROUP"
fi

if ! id "$SPLUNK_USER" > /dev/null 2>&1; then
  log "Creating user: $SPLUNK_USER"
  useradd --system \
    --gid "$SPLUNK_GROUP" \
    --home-dir "$SPLUNK_INSTALL_DIR" \
    --no-create-home \
    --shell /sbin/nologin \
    "$SPLUNK_USER"
fi

# ---------------------------------------------------------------------------
# Download package from S3 (AWS CLI is pre-installed on SSM-managed instances)
# ---------------------------------------------------------------------------
mkdir -p "$TMP_DIR"
log "Downloading package from S3..."
aws s3 cp "s3://$S3_BUCKET/$S3_KEY" "$TMP_DIR/$PACKAGE_FILENAME" \
  --region "$AWS_REGION" \
  --no-progress

log "Download complete: $TMP_DIR/$PACKAGE_FILENAME"

# ---------------------------------------------------------------------------
# Install package based on OS family
# ---------------------------------------------------------------------------
case "$OS_ID" in
  amzn|rhel|centos|rocky|almalinux)
    log "Installing RPM package..."
    rpm -ivh "$TMP_DIR/$PACKAGE_FILENAME"
    ;;
  ubuntu|debian)
    log "Installing DEB package..."
    dpkg -i "$TMP_DIR/$PACKAGE_FILENAME"
    ;;
  *)
    log "ERROR: Unsupported OS: $OS_ID"
    exit 1
    ;;
esac

log "Package installed successfully."

# ---------------------------------------------------------------------------
# Accept license and configure admin credentials on first start
# ---------------------------------------------------------------------------
SPLUNK_BIN="$SPLUNK_INSTALL_DIR/splunkforwarder/bin/splunk"

log "Accepting Splunk license and setting admin credentials..."
"$SPLUNK_BIN" start --accept-license --answer-yes --no-prompt \
  --seed-passwd "$SPLUNK_ADMIN_PASSWORD" 2>&1 | tee -a "$LOG_FILE"

"$SPLUNK_BIN" stop 2>&1 | tee -a "$LOG_FILE"

# ---------------------------------------------------------------------------
# Set deployment server (phone-home to Deployment Server / DS)
# ---------------------------------------------------------------------------
log "Configuring deployment server: $SPLUNK_DEPLOYMENT_SERVER:$SPLUNK_DEPLOYMENT_PORT"
"$SPLUNK_BIN" set deploy-poll \
  "$SPLUNK_DEPLOYMENT_SERVER:$SPLUNK_DEPLOYMENT_PORT" \
  -auth "admin:$SPLUNK_ADMIN_PASSWORD" 2>&1 | tee -a "$LOG_FILE"

# ---------------------------------------------------------------------------
# Set ownership and enable boot-start (systemd)
# ---------------------------------------------------------------------------
log "Setting file ownership to $SPLUNK_USER:$SPLUNK_GROUP ..."
chown -R "$SPLUNK_USER":"$SPLUNK_GROUP" "$SPLUNK_INSTALL_DIR/splunkforwarder"

log "Enabling Splunk as a systemd service..."
"$SPLUNK_BIN" enable boot-start \
  -systemd-managed 1 \
  -user "$SPLUNK_USER" \
  --accept-license --answer-yes --no-prompt 2>&1 | tee -a "$LOG_FILE"

# ---------------------------------------------------------------------------
# Start service via systemd
# ---------------------------------------------------------------------------
log "Starting SplunkForwarder service..."
systemctl daemon-reload
systemctl enable SplunkForwarder
systemctl start SplunkForwarder

# ---------------------------------------------------------------------------
# Verify service is running
# ---------------------------------------------------------------------------
sleep 5
if systemctl is-active --quiet SplunkForwarder; then
  log "SplunkForwarder is running successfully."
else
  log "ERROR: SplunkForwarder failed to start. Check journalctl -u SplunkForwarder"
  exit 1
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
log "Cleaning up temporary files..."
rm -rf "$TMP_DIR"

log "Splunk Universal Forwarder installation completed successfully."
exit 0
