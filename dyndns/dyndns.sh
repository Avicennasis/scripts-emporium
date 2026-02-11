#!/bin/bash
# =============================================================================
# dyndns.sh - Dynamic DNS Client Script
# =============================================================================
# Description:
#   This script retrieves the current external IPv4 address from a public
#   service and syncs it to a remote BIND9 DNS server. It's designed to run
#   periodically via cron to keep your DNS records updated with your dynamic
#   IP address.
#
# Usage:
#   ./dyndns.sh
#
# Prerequisites:
#   - curl: For fetching the external IP address
#   - rsync: For securely transferring the IP file to the remote server
#   - SSH key authentication set up between client and server
#
# Author: Léon "Avic" Simmons
# License: MIT
# Last Updated: 2026
# =============================================================================

# -----------------------------------------------------------------------------
# Strict Mode
# -----------------------------------------------------------------------------
# -e: Exit immediately if any command exits with a non-zero status
# -u: Treat unset variables as an error and exit immediately
# -o pipefail: Return the exit status of the last command in a pipeline that failed
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration Variables
# -----------------------------------------------------------------------------
# Customize these variables to match your environment

# Remote server SSH connection string (user@hostname)
REMOTE_USER="USERNAME"
REMOTE_HOST="HOST.COM"

# Remote directory where the IP file will be stored (on the DNS server)
REMOTE_PATH="/etc/bind/zones"

# Local directory to store the IP address file
LOCAL_DYNDNS_DIR="${HOME}/.dyndns"

# Name of the file that will contain the external IP address
IP_FILENAME="homeip"

# Service URL to retrieve external IP (alternatives: ifconfig.me, ipinfo.io/ip)
IP_SERVICE_URL="http://icanhazip.com"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

# log_message: Prints a timestamped message to stdout
# Arguments:
#   $1 - The message to log
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# validate_ip: Checks if a string is a valid IPv4 address
# Arguments:
#   $1 - The IP address string to validate
# Returns:
#   0 if valid, 1 if invalid
validate_ip() {
    local ip="$1"
    # Regex pattern for a valid IPv4 address (0-255 for each octet)
    local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ $ip =~ $ip_regex ]]; then
        # Additional check: ensure each octet is <= 255
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Main Script Execution
# -----------------------------------------------------------------------------

log_message "Starting Dynamic DNS update..."

# Ensure the local dyndns directory exists
# The -p flag creates parent directories if needed and doesn't error if it exists
if [[ ! -d "$LOCAL_DYNDNS_DIR" ]]; then
    log_message "Creating local directory: $LOCAL_DYNDNS_DIR"
    mkdir -p "$LOCAL_DYNDNS_DIR"
fi

# Fetch the external IP address from the public service
# The -s flag silences curl's progress output
# The -f flag makes curl fail silently on HTTP errors (4xx, 5xx)
# The --max-time flag sets a timeout to prevent hanging
log_message "Fetching external IP from $IP_SERVICE_URL..."
EXTERNAL_IP=$(curl -sf --max-time 30 "$IP_SERVICE_URL" | tr -d '[:space:]')

# Validate the retrieved IP address
if ! validate_ip "$EXTERNAL_IP"; then
    log_message "ERROR: Invalid IP address received: '$EXTERNAL_IP'"
    exit 1
fi

log_message "External IP detected: $EXTERNAL_IP"

# Define the full path to the local IP file
LOCAL_IP_FILE="${LOCAL_DYNDNS_DIR}/${IP_FILENAME}"

# Check if the IP has changed since last update (optional optimization)
if [[ -f "$LOCAL_IP_FILE" ]]; then
    PREVIOUS_IP=$(cat "$LOCAL_IP_FILE" 2>/dev/null || echo "")
    if [[ "$EXTERNAL_IP" == "$PREVIOUS_IP" ]]; then
        log_message "IP unchanged ($EXTERNAL_IP). No update needed."
        exit 0
    fi
    log_message "IP changed from $PREVIOUS_IP to $EXTERNAL_IP"
fi

# Save the external IP to the local file
log_message "Saving IP to $LOCAL_IP_FILE..."
echo "$EXTERNAL_IP" > "$LOCAL_IP_FILE"

# Sync the IP file to the remote DNS server using rsync
# -a: Archive mode (preserves permissions, timestamps, etc.)
# -z: Compress data during transfer
# -e ssh: Use SSH for the transfer
log_message "Syncing IP file to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}..."
rsync -az -e ssh "$LOCAL_IP_FILE" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"

log_message "Dynamic DNS update completed successfully!"
exit 0
