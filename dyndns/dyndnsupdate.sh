#!/bin/bash
# =============================================================================
# dyndnsupdate.sh - Dynamic DNS Server Update Script
# =============================================================================
# Description:
#   This script runs on the BIND9 DNS server and updates zone files with the
#   current dynamic IP address received from the client. It reads the IP from
#   a file synced by the client, substitutes it into the zone template, and
#   reloads the BIND9 service.
#
# Usage:
#   ./dyndnsupdate.sh
#
# Prerequisites:
#   - BIND9 installed and configured
#   - Proper permissions to modify zone files
#   - The rndc utility available and configured
#   - Zone template file (HOME.example) with HOMEREPLACEME placeholder
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

# Directory containing BIND zone files
ZONES_DIR="/etc/bind/zones"

# Template file containing the zone structure with placeholder
TEMPLATE_FILE="HOME.example"

# Intermediate file for processing (before copying to final zone file)
WORKING_FILE="HOME"

# Final zone file name for the domain
ZONE_FILE="db.HOST.COM"

# File containing the current external IP (synced from client)
IP_FILE="homeip"

# Placeholder string in the template that will be replaced with the actual IP
IP_PLACEHOLDER="HOMEREPLACEME"

# Enable backup creation before modifying files (true/false)
ENABLE_BACKUP=true

# Backup directory (used if ENABLE_BACKUP is true)
BACKUP_DIR="${ZONES_DIR}/backups"

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

# create_backup: Creates a timestamped backup of a file
# Arguments:
#   $1 - The file to backup
create_backup() {
    local file="$1"
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${BACKUP_DIR}/$(basename "$file").${timestamp}.bak"
    
    # Ensure the backup directory exists
    mkdir -p "$BACKUP_DIR"
    
    # Copy the file to the backup location
    cp "$file" "$backup_file"
    log_message "Backup created: $backup_file"
}

# -----------------------------------------------------------------------------
# Main Script Execution
# -----------------------------------------------------------------------------

log_message "Starting BIND zone update..."

# Change to the zones directory
cd "$ZONES_DIR" || {
    log_message "ERROR: Failed to change to zones directory: $ZONES_DIR"
    exit 1
}

# Verify the IP file exists and is readable
if [[ ! -f "$IP_FILE" ]]; then
    log_message "ERROR: IP file not found: ${ZONES_DIR}/${IP_FILE}"
    log_message "Make sure the client has synced the IP file."
    exit 1
fi

# Read and validate the external IP address
# tr removes any whitespace/newlines that might be present
EXTERNAL_IP=$(tr -d '[:space:]' < "$IP_FILE")

if [[ -z "$EXTERNAL_IP" ]]; then
    log_message "ERROR: IP file is empty: ${ZONES_DIR}/${IP_FILE}"
    exit 1
fi

if ! validate_ip "$EXTERNAL_IP"; then
    log_message "ERROR: Invalid IP address in file: '$EXTERNAL_IP'"
    exit 1
fi

log_message "External IP to use: $EXTERNAL_IP"

# Verify the template file exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_message "ERROR: Template file not found: ${ZONES_DIR}/${TEMPLATE_FILE}"
    exit 1
fi

# Create backups of the current zone file if enabled
if [[ "$ENABLE_BACKUP" == true ]] && [[ -f "$ZONE_FILE" ]]; then
    create_backup "$ZONE_FILE"
fi

# Copy the template to the working file
# This gives us a fresh copy to work with each time
log_message "Creating working copy from template..."
cp "$TEMPLATE_FILE" "$WORKING_FILE"

# Replace the placeholder with the actual IP address
# Using sed with a delimiter that won't conflict with IP addresses
# The -i flag edits the file in place
log_message "Substituting IP address in zone file..."
sed -i "s/${IP_PLACEHOLDER}/${EXTERNAL_IP}/g" "$WORKING_FILE"

# Verify the substitution was successful
if grep -q "$IP_PLACEHOLDER" "$WORKING_FILE"; then
    log_message "WARNING: Placeholder still present in working file. Substitution may have failed."
fi

# Copy the updated working file to the final zone file
log_message "Copying to final zone file: $ZONE_FILE"
cp "$WORKING_FILE" "$ZONE_FILE"

# Reload BIND to apply the changes
# rndc reload tells BIND to reload its zone files without restarting
log_message "Reloading BIND9 configuration..."
if rndc reload; then
    log_message "BIND9 reloaded successfully!"
else
    log_message "ERROR: Failed to reload BIND9. Check rndc configuration."
    exit 1
fi

log_message "Zone update completed successfully!"
log_message "The 'home' subdomain now points to: $EXTERNAL_IP"
exit 0
