#!/bin/bash
# ==============================================================================
# Janitor Script
# ==============================================================================
#
# Description:
#   This script automates the cleanup of temporary files in a specified directory.
#   It identifies files older than a configured number of days, logs their total
#   size and filenames, and then permanently deletes them.
#
#   Key Features:
#   - targeting of files older than RETENTION_DAYS (default: 30)
#   - detailed logging of deleted files and their sizes
#   - monthly log rotation
#   - safety checks to prevent unintended deletions
#
# Usage:
#   ./janitor.sh [OPTIONS]
#
#   Options:
#     --email EMAIL       Send cleanup report to specified email address
#     --html-off          Send plain text email instead of HTML (requires --email)
#
# Author: Léon "Avic" Simmons (@Avicennasis)
# License: MIT License
# Updated: 2026
#
# ==============================================================================

# Enable strict mode for better error handling
# -e: Exit immediately if a command exits with a non-zero status
# -u: Treat unset variables as an error
# -o pipefail: pipeline return status is the value of the last (failed) command
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

# Parse command line arguments
EMAIL_RECIPIENT=""
USE_HTML=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            EMAIL_RECIPIENT="$2"
            shift 2
            ;;
        --html-off)
            USE_HTML=false
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--email EMAIL] [--html-off]" >&2
            exit 1
            ;;
    esac
done

# Directory to clean up
# IMPORTANT: Update this path to your actual temp directory
TARGET_DIR="/path/to/cleanup"

# Number of days to keep files
RETENTION_DAYS=30

# Base directory for logs
LOG_BASE_DIR="${HOME}/logs/janitor"

# Date formats for logging
CURRENT_YEAR_MONTH=$(date -u +%Y/%m)
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# ==============================================================================
# Email Functions
# ==============================================================================

# Function to convert bytes to human-readable format
human_readable_size() {
    local bytes=$1
    if (( bytes < 1024 )); then
        echo "${bytes} B"
    elif (( bytes < 1048576 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}") KB"
    elif (( bytes < 1073741824 )); then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}") MB"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"
    fi
}

# Function to send email notification
send_email_notification() {
    local recipient="$1"
    local files_count="$2"
    local cleanup_size="$3"
    local new_total="$4"
    local use_html="$5"

    local subject="Janitor Cleanup Report - $TIMESTAMP"
    local cleanup_size_hr=$(human_readable_size "$cleanup_size")
    local new_total_hr=$(human_readable_size "$new_total")

    if [ "$use_html" = true ]; then
        # Generate HTML email
        local html_body=$(cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: #ffffff;
            border-radius: 8px;
            padding: 30px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
            margin-top: 0;
        }
        .summary-table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            background-color: #fff;
        }
        .summary-table th {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        .summary-table td {
            padding: 12px;
            border-bottom: 1px solid #e0e0e0;
        }
        .summary-table tr:last-child td {
            border-bottom: none;
        }
        .summary-table tr:nth-child(even) {
            background-color: #f8f9fa;
        }
        .metric-label {
            font-weight: 600;
            color: #555;
        }
        .metric-value {
            color: #2c3e50;
            font-weight: 500;
        }
        .success-badge {
            display: inline-block;
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            color: white;
            padding: 8px 16px;
            border-radius: 20px;
            font-weight: 600;
            margin: 20px 0;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 2px solid #e0e0e0;
            color: #777;
            font-size: 0.9em;
        }
        .highlight {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
            padding: 2px 6px;
            border-radius: 3px;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧹 Janitor Cleanup Report</h1>
        <div class="success-badge">✅ Cleanup Completed Successfully</div>

        <table class="summary-table">
            <thead>
                <tr>
                    <th colspan="2">Cleanup Summary</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td class="metric-label">📅 Timestamp</td>
                    <td class="metric-value">$TIMESTAMP</td>
                </tr>
                <tr>
                    <td class="metric-label">📁 Target Directory</td>
                    <td class="metric-value">$TARGET_DIR</td>
                </tr>
                <tr>
                    <td class="metric-label">⏱️ Retention Period</td>
                    <td class="metric-value">$RETENTION_DAYS days</td>
                </tr>
                <tr>
                    <td class="metric-label">🗑️ Files Deleted</td>
                    <td class="metric-value"><span class="highlight">$files_count</span> files</td>
                </tr>
                <tr>
                    <td class="metric-label">💾 Space Freed</td>
                    <td class="metric-value"><span class="highlight">$cleanup_size_hr</span> ($cleanup_size bytes)</td>
                </tr>
                <tr>
                    <td class="metric-label">📊 Total Deleted (All Time)</td>
                    <td class="metric-value"><span class="highlight">$new_total_hr</span> ($new_total bytes)</td>
                </tr>
            </tbody>
        </table>

        <div class="footer">
            <strong>📋 Logs Location:</strong><br>
            Deleted files: <code>$DELETED_FILES_LOG</code><br>
            Total size: <code>$TOTAL_SIZE_LOG</code>
        </div>
    </div>
</body>
</html>
EOF
)
        # Send HTML email
        echo "$html_body" | mail -s "$subject" -a "Content-Type: text/html; charset=UTF-8" "$recipient"
    else
        # Generate plain text email
        local text_body=$(cat <<EOF
Janitor Cleanup Report
======================

Cleanup completed successfully!

Summary:
--------
Timestamp:              $TIMESTAMP
Target Directory:       $TARGET_DIR
Retention Period:       $RETENTION_DAYS days
Files Deleted:          $files_count files
Space Freed:            $cleanup_size_hr ($cleanup_size bytes)
Total Deleted (All):    $new_total_hr ($new_total bytes)

Logs:
-----
Deleted files:          $DELETED_FILES_LOG
Total size:             $TOTAL_SIZE_LOG

---
Generated by Janitor
EOF
)
        # Send plain text email
        echo "$text_body" | mail -s "$subject" "$recipient"
    fi

    echo "[$TIMESTAMP] Email notification sent to $recipient"
}

# ==============================================================================
# Main Execution
# ==============================================================================

echo "[$TIMESTAMP] Starting Janitor cleanup..."

# 1. Validation
# -------------
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory '$TARGET_DIR' does not exist." >&2
    exit 1
fi

if [ -z "$(ls -A "$TARGET_DIR")" ]; then
    echo "[$TIMESTAMP] Target directory is empty. Nothing to clean."
    exit 0
fi

# 2. Setup Logging
# ----------------
LOG_DIR="${LOG_BASE_DIR}/${CURRENT_YEAR_MONTH}"
mkdir -p "$LOG_DIR"

TOTAL_SIZE_LOG="${LOG_BASE_DIR}/tempsizeinbytes.txt"
DELETED_FILES_LOG="${LOG_DIR}/deleted.txt"

# Ensure the total size log exists
if [ ! -f "$TOTAL_SIZE_LOG" ]; then
    echo "Creating new total size log..."
    echo 0 > "$TOTAL_SIZE_LOG"
fi

# 3. Analyze Files to Delete
# --------------------------
echo "[$TIMESTAMP] analyzing files older than $RETENTION_DAYS days in $TARGET_DIR..."

# Create a temporary file to hold the list of files to process
# We use mktemp for safety and automatic cleanup
FILES_TO_DELETE_LIST=$(mktemp)
trap 'rm -f "$FILES_TO_DELETE_LIST"' EXIT

# Find files older than RETENTION_DAYS
# We use -type f to only target files, ignoring directories for safety
find "$TARGET_DIR" -type f -mtime +$RETENTION_DAYS -print0 > "$FILES_TO_DELETE_LIST"

# Check if we found any files
if [ ! -s "$FILES_TO_DELETE_LIST" ]; then
    echo "[$TIMESTAMP] No files found older than $RETENTION_DAYS days."
    exit 0
fi

# 4. Calculate Size and Log
# -------------------------
echo "[$TIMESTAMP] Calculating cleanup size and updating logs..."

# Count files to be deleted
FILES_COUNT=$(grep -cz '' "$FILES_TO_DELETE_LIST" || echo "0")

# Calculate total size of files to be deleted (in bytes)
# 'du --files0-from' is efficient for processing the list from find -print0
# We calculate the sum of sizes
CLEANUP_SIZE=$(du -bc --files0-from="$FILES_TO_DELETE_LIST" | grep 'total$' | awk '{print $1}')

# Log the filenames (converting null delimiters to newlines for readability in log)
# We append to the monthly deleted.txt log
xargs -0 -a "$FILES_TO_DELETE_LIST" ls -lh >> "$DELETED_FILES_LOG"

# Update the cumulative total size deleted
CURRENT_TOTAL=$(cat "$TOTAL_SIZE_LOG")
NEW_TOTAL=$(awk "BEGIN {print $CURRENT_TOTAL + $CLEANUP_SIZE}")
echo "$NEW_TOTAL" > "$TOTAL_SIZE_LOG"

echo "[$TIMESTAMP] Size to delete: $CLEANUP_SIZE bytes"
echo "[$TIMESTAMP] New cumulative total deleted: $NEW_TOTAL bytes"

# 5. Delete Files
# ---------------
echo "[$TIMESTAMP] Deleting files..."

# Perform the deletion
xargs -0 -a "$FILES_TO_DELETE_LIST" rm -f

echo "[$TIMESTAMP] Done! Cleanup complete."

# 6. Send Email Notification (if requested)
# ------------------------------------------
if [ -n "$EMAIL_RECIPIENT" ]; then
    send_email_notification "$EMAIL_RECIPIENT" "$FILES_COUNT" "$CLEANUP_SIZE" "$NEW_TOTAL" "$USE_HTML"
fi
