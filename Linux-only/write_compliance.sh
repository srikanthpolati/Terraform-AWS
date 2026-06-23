#!/usr/bin/env bash
# =============================================================================
# Write Consolidated Compliance Data to SSM Compliance & Inventory (Linux)
# =============================================================================
# Reads result files written by each compliance script and posts to:
#   1. SSM Compliance (Custom:MandatoryApplications) - visible in dashboard
#   2. SSM Inventory (Custom:MandatoryAppCompliance) - queryable in inventory
# =============================================================================

set -euo pipefail

AWS_REGION="${AWSRegion:-ap-southeast-2}"
ENVIRONMENT="${Environment:-unknown}"
COMPLIANCE_DIR="/tmp/ssm_compliance_results"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')][${1:-INFO}] ${2}"; }

# --------------------------------------------------------------------------
# Get instance ID from metadata service (IMDSv2 compatible)
# --------------------------------------------------------------------------
get_instance_id() {
    # Try IMDSv2 first
    local token
    token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null) || true

    if [ -n "$token" ]; then
        curl -s -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/meta-data/instance-id" 2>/dev/null
    else
        # Fallback IMDSv1
        curl -s "http://169.254.169.254/latest/meta-data/instance-id" 2>/dev/null
    fi
}

# --------------------------------------------------------------------------
# Parse a result file and return values
# --------------------------------------------------------------------------
parse_result() {
    local file="$1"
    local key="$2"
    grep "^${key}=" "$file" 2>/dev/null | cut -d'=' -f2- | tr -d '"'
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
log INFO "=== Writing SSM Compliance Data ==="

INSTANCE_ID=$(get_instance_id)
if [ -z "$INSTANCE_ID" ]; then
    log ERROR "Could not determine instance ID. Exiting."
    exit 1
fi
log INFO "Instance ID: $INSTANCE_ID"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# --------------------------------------------------------------------------
# Load results from each compliance script
# --------------------------------------------------------------------------
declare -A APPS
RESULT_FILES=("splunk" "qualys" "cloudwatch" "carbonblack")

TOTAL=0
COMPLIANT_COUNT=0
NON_COMPLIANT_COUNT=0

# Build SSM compliance items JSON array
COMPLIANCE_ITEMS_JSON="["
INVENTORY_ITEMS_JSON="["
FIRST=true

for app in "${RESULT_FILES[@]}"; do
    RESULT_FILE="$COMPLIANCE_DIR/${app}.env"

    if [ ! -f "$RESULT_FILE" ]; then
        log WARN "Result file missing for $app — marking NON_COMPLIANT."
        APP_NAME="$(tr '[:lower:]' '[:upper:]' <<< "${app:0:1}")${app:1}"
        TARGET="UNKNOWN"
        INSTALLED="SCRIPT_ERROR"
        STATUS="NON_COMPLIANT"
    else
        APP_NAME=$(parse_result "$RESULT_FILE" "APP_NAME")
        TARGET=$(parse_result "$RESULT_FILE" "TARGET_VERSION")
        INSTALLED=$(parse_result "$RESULT_FILE" "INSTALLED_VERSION")
        IS_COMPLIANT_VAL=$(parse_result "$RESULT_FILE" "IS_COMPLIANT")
        STATUS=$([ "$IS_COMPLIANT_VAL" = "true" ] && echo "COMPLIANT" || echo "NON_COMPLIANT")
    fi

    TOTAL=$((TOTAL + 1))
    if [ "$STATUS" = "COMPLIANT" ]; then
        COMPLIANT_COUNT=$((COMPLIANT_COUNT + 1))
    else
        NON_COMPLIANT_COUNT=$((NON_COMPLIANT_COUNT + 1))
    fi

    log INFO "$APP_NAME: $STATUS (Installed=$INSTALLED, Target=$TARGET)"

    COMMENT="Target: ${TARGET} | Installed: ${INSTALLED}"

    if [ "$FIRST" = "true" ]; then
        FIRST=false
    else
        COMPLIANCE_ITEMS_JSON+=","
        INVENTORY_ITEMS_JSON+=","
    fi

    COMPLIANCE_ITEMS_JSON+="{\"Id\":\"${APP_NAME}\",\"Title\":\"${APP_NAME} Version Compliance\",\"Status\":\"${STATUS}\",\"Severity\":\"CRITICAL\",\"Details\":{\"Comment\":\"${COMMENT}\"}}"

    INVENTORY_ITEMS_JSON+="{\"ApplicationName\":\"${APP_NAME}\",\"ComplianceStatus\":\"${STATUS}\",\"InstalledVersion\":\"${INSTALLED}\",\"TargetVersion\":\"${TARGET}\",\"OS\":\"Linux\",\"LastChecked\":\"${TIMESTAMP}\",\"Environment\":\"${ENVIRONMENT}\"}"
done

COMPLIANCE_ITEMS_JSON+="]"
INVENTORY_ITEMS_JSON+="]"

# --------------------------------------------------------------------------
# Write to SSM Compliance
# --------------------------------------------------------------------------
log INFO "Writing compliance data to SSM..."

EXEC_SUMMARY="{\"ExecutionTime\":\"${TIMESTAMP}\",\"ExecutionType\":\"Command\"}"

aws ssm put-compliance-items \
    --resource-id "$INSTANCE_ID" \
    --resource-type "ManagedInstance" \
    --compliance-type "Custom:MandatoryApplications" \
    --execution-summary "$EXEC_SUMMARY" \
    --items "$COMPLIANCE_ITEMS_JSON" \
    --region "$AWS_REGION"

if [ $? -eq 0 ]; then
    log INFO "Compliance data written to SSM successfully."
else
    log ERROR "Failed to write compliance data to SSM."
fi

# --------------------------------------------------------------------------
# Write to SSM Inventory (Custom Schema)
# --------------------------------------------------------------------------
log INFO "Writing custom inventory data to SSM Inventory..."

INVENTORY_PAYLOAD="[{
    \"TypeName\": \"Custom:MandatoryAppCompliance\",
    \"SchemaVersion\": \"1.0\",
    \"CaptureTime\": \"${TIMESTAMP}\",
    \"Content\": ${INVENTORY_ITEMS_JSON}
}]"

aws ssm put-inventory \
    --instance-id "$INSTANCE_ID" \
    --items "$INVENTORY_PAYLOAD" \
    --region "$AWS_REGION"

if [ $? -eq 0 ]; then
    log INFO "Custom inventory data written to SSM Inventory."
else
    log WARN "Failed to write custom inventory data."
fi

# --------------------------------------------------------------------------
# Summary and exit code
# --------------------------------------------------------------------------
log INFO "=== COMPLIANCE SUMMARY ==="
log INFO "Total Applications : $TOTAL"
log INFO "Compliant          : $COMPLIANT_COUNT"
log INFO "Non-Compliant      : $NON_COMPLIANT_COUNT"

if [ "$NON_COMPLIANT_COUNT" -gt 0 ]; then
    log WARN "Instance $INSTANCE_ID has $NON_COMPLIANT_COUNT non-compliant mandatory application(s)."
    exit 1  # Non-zero marks SSM association as failed — raises visibility in console
else
    log INFO "Instance $INSTANCE_ID is FULLY COMPLIANT with all mandatory applications."
    exit 0
fi
