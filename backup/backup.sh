#!/usr/bin/env bash
# =============================================================================
# backup.sh - Modern Backup Script (2026 Edition)
# =============================================================================
#
# DESCRIPTION:
#   A robust backup utility that creates both archival (full history) and
#   incremental (synchronized) backups of important directories. This script
#   uses rsync for one-way archival backups and unison for bidirectional
#   synchronization.
#
# AUTHOR:
#   Léon "Avic" Simmons
#
# LICENSE:
#   MIT License - See LICENSE file for details
#
# USAGE:
#   ./backup.sh [OPTIONS]
#
# OPTIONS:
#   -h, --help              Show this help message and exit
#   -n, --dry-run           Perform a trial run with no changes made
#   -v, --verbose           Enable verbose output for debugging
#   -q, --quiet             Suppress non-error output
#   --email-on-success      Send email notification on successful backup
#   --email-on-failure      Send email notification on failed backup
#   --email-always          Send email notification regardless of outcome
#   --email-to <address>    Email address to send notifications to
#   --html-off              Disable HTML formatting in email (use plain text)
#
# =============================================================================

# -----------------------------------------------------------------------------
# BASH STRICT MODE
# -----------------------------------------------------------------------------
# These settings make the script more robust by:
#   - set -e: Exit immediately if any command fails (non-zero exit status)
#   - set -u: Treat unset variables as an error (prevents typos)
#   - set -o pipefail: Catch errors in piped commands (not just the last one)
# -----------------------------------------------------------------------------
set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
# Define your backup sources and destinations here. Modify these arrays to
# customize which directories get backed up and where they go.
# -----------------------------------------------------------------------------

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Lock file to prevent concurrent executions
readonly LOCK_FILE="/tmp/${SCRIPT_NAME}.lock"

# Log file location (with timestamp for unique log files)
readonly LOG_DIR="${HOME}/.logs/backup"
readonly LOG_FILE="${LOG_DIR}/backup_$(date +%Y%m%d_%H%M%S).log"

# Source directories to back up (relative to home directory)
# Add or remove directories from this array as needed
readonly SOURCE_DIRS=(
    "Downloads"
    "Documents"
    "scripts"
    "projects"
)

# Individual files to back up (will be copied with .txt extension for safety)
readonly SOURCE_FILES=(
    ".bash_history"
    ".bashrc"
    ".profile"
)

# Backup destination base paths
# Modify these to match your actual backup storage locations
readonly BACKUP_BASE="/mnt/backup"
readonly ARCHIVE_DIR="${BACKUP_BASE}/backup-archive"
readonly SYNC_DIR="${BACKUP_BASE}/backup-sync"
readonly MIRROR_SOURCE="${BACKUP_BASE}"
readonly MIRROR_DEST="/mnt/usb/backup-mirror"

# Patterns to exclude from backups (trash, cache, temp files, etc.)
readonly EXCLUDE_PATTERNS=(
    ".Trash-*"
    ".cache"
    "*.tmp"
    "*.swp"
    "__pycache__"
    "node_modules"
    ".git"
)

# -----------------------------------------------------------------------------
# RUNTIME OPTIONS (set via command-line arguments)
# -----------------------------------------------------------------------------
DRY_RUN=false
VERBOSE=false
QUIET=false

# Email notification options
EMAIL_ON_SUCCESS=false
EMAIL_ON_FAILURE=false
EMAIL_TO=""
EMAIL_HTML=true  # HTML formatting enabled by default

# -----------------------------------------------------------------------------
# COLOR DEFINITIONS
# -----------------------------------------------------------------------------
# ANSI color codes for prettier terminal output. These make it easier to
# quickly identify success, warning, and error messages at a glance.
# -----------------------------------------------------------------------------
readonly COLOR_RESET="\033[0m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_CYAN="\033[0;36m"

# -----------------------------------------------------------------------------
# LOGGING FUNCTIONS
# -----------------------------------------------------------------------------
# These functions provide consistent, timestamped logging to both the console
# and a log file. Different log levels help categorize message importance.
# -----------------------------------------------------------------------------

# Ensure log directory exists
setup_logging() {
    # Create log directory if it doesn't exist
    # The -p flag creates parent directories as needed and doesn't error if exists
    mkdir -p "${LOG_DIR}"
}

# Write a timestamped message to the log file
log_to_file() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${message}" >> "${LOG_FILE}"
}

# Display an informational message (blue)
log_info() {
    local message="$1"
    log_to_file "INFO: ${message}"
    if [[ "${QUIET}" != true ]]; then
        echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} ${message}"
    fi
}

# Display a success message (green)
log_success() {
    local message="$1"
    log_to_file "SUCCESS: ${message}"
    if [[ "${QUIET}" != true ]]; then
        echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} ${message}"
    fi
}

# Display a warning message (yellow)
log_warn() {
    local message="$1"
    log_to_file "WARNING: ${message}"
    if [[ "${QUIET}" != true ]]; then
        echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} ${message}" >&2
    fi
}

# Display an error message (red) - always shown even in quiet mode
log_error() {
    local message="$1"
    log_to_file "ERROR: ${message}"
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} ${message}" >&2
}

# Display a debug message (cyan) - only shown in verbose mode
log_debug() {
    local message="$1"
    log_to_file "DEBUG: ${message}"
    if [[ "${VERBOSE}" == true ]]; then
        echo -e "${COLOR_CYAN}[DEBUG]${COLOR_RESET} ${message}"
    fi
}

# -----------------------------------------------------------------------------
# UTILITY FUNCTIONS
# -----------------------------------------------------------------------------

# Display the help message with usage information
show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Modern Backup Utility

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

DESCRIPTION:
    Creates archival and incremental backups of configured directories.
    - Archive backups: Full history preserved (using rsync)
    - Sync backups: Bidirectional synchronization (using unison)

OPTIONS:
    -h, --help              Show this help message and exit
    -n, --dry-run           Perform a trial run with no changes made
    -v, --verbose           Enable verbose output for debugging
    -q, --quiet             Suppress non-error output
    --email-on-success      Send email notification on successful backup
    --email-on-failure      Send email notification on failed backup
    --email-always          Send email notification regardless of outcome
    --email-to <address>    Email address to send notifications to
    --html-off              Disable HTML formatting in email (use plain text)

EXAMPLES:
    ${SCRIPT_NAME}                                          # Run backup with default settings
    ${SCRIPT_NAME} --dry-run                                # Preview what would be backed up
    ${SCRIPT_NAME} -v                                       # Run with verbose debugging output
    ${SCRIPT_NAME} --email-always --email-to you@example.com  # Run with email notifications

CONFIGURATION:
    Edit the CONFIGURATION section in this script to customize:
    - SOURCE_DIRS: Directories to back up
    - SOURCE_FILES: Individual files to back up
    - BACKUP_BASE: Base path for backup storage
    - EXCLUDE_PATTERNS: Files/folders to exclude

AUTHOR:
    Léon "Avic" Simmons

LICENSE:
    MIT License - See LICENSE file for details
EOF
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=true
                log_info "Dry-run mode enabled - no changes will be made"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                log_debug "Verbose mode enabled"
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --email-on-success)
                EMAIL_ON_SUCCESS=true
                shift
                ;;
            --email-on-failure)
                EMAIL_ON_FAILURE=true
                shift
                ;;
            --email-always)
                EMAIL_ON_SUCCESS=true
                EMAIL_ON_FAILURE=true
                shift
                ;;
            --email-to)
                if [[ -z "${2:-}" ]] || [[ "${2}" == -* ]]; then
                    log_error "--email-to requires an email address"
                    exit 1
                fi
                EMAIL_TO="$2"
                shift 2
                ;;
            --html-off)
                EMAIL_HTML=false
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Check if required commands are available on the system
check_dependencies() {
    local missing_deps=()

    # Check for rsync (required for archival backups)
    if ! command -v rsync &> /dev/null; then
        missing_deps+=("rsync")
    fi

    # Check for unison (required for bidirectional sync)
    if ! command -v unison &> /dev/null; then
        missing_deps+=("unison")
    fi

    # If any dependencies are missing, report and exit
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install them using your package manager:"
        log_error "  Ubuntu/Debian: sudo apt install ${missing_deps[*]}"
        log_error "  Fedora/RHEL:   sudo dnf install ${missing_deps[*]}"
        log_error "  macOS:         brew install ${missing_deps[*]}"
        exit 1
    fi

    log_debug "All required dependencies are installed"
}

# Acquire a lock to prevent multiple instances from running simultaneously
acquire_lock() {
    # Use file descriptor 200 for the lock file
    exec 200>"${LOCK_FILE}"

    # Try to acquire an exclusive lock (non-blocking)
    # flock -n: non-blocking; returns immediately if lock can't be acquired
    if ! flock -n 200; then
        log_error "Another instance of ${SCRIPT_NAME} is already running"
        log_error "If you're sure no other instance is running, remove: ${LOCK_FILE}"
        exit 1
    fi

    # Write our PID to the lock file for debugging purposes
    echo $$ >&200
    log_debug "Lock acquired (PID: $$)"
}

# Release the lock file on exit
release_lock() {
    # Remove the lock file if it exists
    if [[ -f "${LOCK_FILE}" ]]; then
        rm -f "${LOCK_FILE}"
        log_debug "Lock released"
    fi
}

# Build rsync exclude arguments from the EXCLUDE_PATTERNS array
build_exclude_args() {
    local args=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        args+="--exclude=${pattern} "
    done
    echo "${args}"
}

# -----------------------------------------------------------------------------
# BACKUP FUNCTIONS
# -----------------------------------------------------------------------------
# These functions perform the actual backup operations. Each function handles
# a specific type of backup with appropriate logging and error handling.
# -----------------------------------------------------------------------------

# Perform archival backup of a directory using rsync
# Archives preserve ALL files, even if deleted from source
backup_archive_directory() {
    local source_dir="$1"
    local source_path="${HOME}/${source_dir}"
    local dest_path="${ARCHIVE_DIR}/${source_dir}"

    # Skip if source doesn't exist
    if [[ ! -d "${source_path}" ]]; then
        log_warn "Source directory does not exist: ${source_path}"
        return 0
    fi

    log_info "Archiving: ${source_dir}"
    log_debug "  Source: ${source_path}"
    log_debug "  Destination: ${dest_path}"

    # Build the rsync command
    # -a: archive mode (preserves permissions, timestamps, etc.)
    # -h: human-readable sizes
    # --info=progress2: show overall progress
    local rsync_opts="-ah"
    local exclude_args
    exclude_args=$(build_exclude_args)

    # Add dry-run flag if enabled
    if [[ "${DRY_RUN}" == true ]]; then
        rsync_opts+="n"
    fi

    # Add verbose flag if enabled
    if [[ "${VERBOSE}" == true ]]; then
        rsync_opts+="v"
    fi

    # Create destination directory if it doesn't exist
    if [[ "${DRY_RUN}" != true ]]; then
        mkdir -p "${dest_path}"
    fi

    # Execute rsync with dynamically built options
    # shellcheck disable=SC2086
    if rsync ${rsync_opts} ${exclude_args} "${source_path}/" "${dest_path}/"; then
        log_success "Archived: ${source_dir}"
    else
        log_error "Failed to archive: ${source_dir}"
        return 1
    fi
}

# Perform archival backup of an individual file using rsync
backup_archive_file() {
    local source_file="$1"
    local source_path="${HOME}/${source_file}"
    # Convert dotfiles to .txt extension for easier viewing
    local dest_name="${source_file#.}.txt"
    local dest_path="${ARCHIVE_DIR}/${dest_name}"

    # Skip if source doesn't exist
    if [[ ! -f "${source_path}" ]]; then
        log_warn "Source file does not exist: ${source_path}"
        return 0
    fi

    log_info "Archiving file: ${source_file}"

    # Build rsync options
    local rsync_opts="-ah"

    if [[ "${DRY_RUN}" == true ]]; then
        rsync_opts+="n"
    fi

    if [[ "${VERBOSE}" == true ]]; then
        rsync_opts+="v"
    fi

    # Execute rsync
    # shellcheck disable=SC2086
    if rsync ${rsync_opts} "${source_path}" "${dest_path}"; then
        log_success "Archived file: ${source_file} -> ${dest_name}"
    else
        log_error "Failed to archive file: ${source_file}"
        return 1
    fi
}

# Perform bidirectional sync of a directory using unison
# Sync directories mirror changes in BOTH directions (including deletions)
backup_sync_directory() {
    local source_dir="$1"
    local source_path="${HOME}/${source_dir}"
    local dest_path="${SYNC_DIR}/${source_dir}"

    # Skip if source doesn't exist
    if [[ ! -d "${source_path}" ]]; then
        log_warn "Source directory does not exist: ${source_path}"
        return 0
    fi

    log_info "Syncing: ${source_dir}"
    log_debug "  Source: ${source_path}"
    log_debug "  Destination: ${dest_path}"

    # Build unison options
    # -auto: automatically accept default actions
    # -batch: run without user interaction
    # -silent: suppress status messages (unless verbose)
    local unison_opts="-auto -batch"

    if [[ "${DRY_RUN}" == true ]]; then
        unison_opts+=" -testserver"
        log_info "  (Dry-run: testing connection only)"
    fi

    if [[ "${QUIET}" == true ]]; then
        unison_opts+=" -silent"
    fi

    # Create destination directory if it doesn't exist
    if [[ "${DRY_RUN}" != true ]]; then
        mkdir -p "${dest_path}"
    fi

    # Execute unison
    # Note: unison requires both paths to exist
    # shellcheck disable=SC2086
    if unison ${unison_opts} "${source_path}" "${dest_path}"; then
        log_success "Synced: ${source_dir}"
    else
        log_error "Failed to sync: ${source_dir}"
        return 1
    fi
}

# Mirror the entire backup location to an external drive
# This creates a backup of the backups for additional redundancy
backup_mirror() {
    log_info "Creating mirror backup (backup of backups)"
    log_debug "  Source: ${MIRROR_SOURCE}"
    log_debug "  Destination: ${MIRROR_DEST}"

    # Check if mirror destination exists
    if [[ ! -d "${MIRROR_DEST}" ]]; then
        log_warn "Mirror destination not available: ${MIRROR_DEST}"
        log_warn "Skipping mirror backup (external drive may not be mounted)"
        return 0
    fi

    # Build unison options for mirroring
    local unison_opts="-auto -batch"

    if [[ "${DRY_RUN}" == true ]]; then
        unison_opts+=" -testserver"
    fi

    if [[ "${QUIET}" == true ]]; then
        unison_opts+=" -silent"
    fi

    # Execute unison for mirroring
    # shellcheck disable=SC2086
    if unison ${unison_opts} "${MIRROR_SOURCE}" "${MIRROR_DEST}"; then
        log_success "Mirror backup complete"
    else
        log_error "Failed to create mirror backup"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# EMAIL NOTIFICATION FUNCTIONS
# -----------------------------------------------------------------------------
# These functions send email notifications about backup results
# -----------------------------------------------------------------------------

# Generate HTML email body
generate_html_email() {
    local status="$1"
    local success_count="$2"
    local failure_count="$3"
    local duration="$4"
    local hostname
    hostname=$(hostname)
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Set colors based on status
    local status_color="#28a745"  # Green for success
    local status_text="SUCCESS"
    if [[ "${status}" == "failure" ]]; then
        status_color="#dc3545"  # Red for failure
        status_text="FAILURE"
    fi

    cat << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; background-color: #f4f4f4; padding: 20px; }
        .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px 20px; text-align: center; }
        .header h1 { margin: 0; font-size: 28px; }
        .status-badge { display: inline-block; padding: 8px 20px; margin-top: 15px; border-radius: 20px; font-weight: bold; font-size: 16px; background: ${status_color}; }
        .content { padding: 30px; }
        .info-table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .info-table th { background: #f8f9fa; padding: 12px; text-align: left; border-bottom: 2px solid #dee2e6; font-weight: 600; color: #495057; }
        .info-table td { padding: 12px; border-bottom: 1px solid #dee2e6; }
        .info-table tr:last-child td { border-bottom: none; }
        .stats { display: flex; justify-content: space-around; margin: 25px 0; }
        .stat-box { text-align: center; padding: 20px; background: #f8f9fa; border-radius: 8px; flex: 1; margin: 0 10px; }
        .stat-number { font-size: 36px; font-weight: bold; color: #667eea; }
        .stat-label { color: #6c757d; margin-top: 5px; font-size: 14px; }
        .footer { background: #f8f9fa; padding: 20px; text-align: center; color: #6c757d; font-size: 12px; }
        .success-count { color: #28a745; }
        .failure-count { color: #dc3545; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔄 Backup Report</h1>
            <div class="status-badge">${status_text}</div>
        </div>
        <div class="content">
            <h2 style="color: #495057; margin-top: 0;">Backup Summary</h2>

            <table class="info-table">
                <tr>
                    <th>Property</th>
                    <th>Value</th>
                </tr>
                <tr>
                    <td><strong>Hostname</strong></td>
                    <td>${hostname}</td>
                </tr>
                <tr>
                    <td><strong>Timestamp</strong></td>
                    <td>${timestamp}</td>
                </tr>
                <tr>
                    <td><strong>Duration</strong></td>
                    <td>${duration} seconds</td>
                </tr>
                <tr>
                    <td><strong>Status</strong></td>
                    <td style="font-weight: bold; color: ${status_color};">${status_text}</td>
                </tr>
            </table>

            <div class="stats">
                <div class="stat-box">
                    <div class="stat-number success-count">${success_count}</div>
                    <div class="stat-label">Successful Operations</div>
                </div>
                <div class="stat-box">
                    <div class="stat-number failure-count">${failure_count}</div>
                    <div class="stat-label">Failed Operations</div>
                </div>
            </div>

            <p style="margin-top: 25px; color: #6c757d;">
                <strong>Log file:</strong> ${LOG_FILE}
            </p>
        </div>
        <div class="footer">
            <p>Generated by ${SCRIPT_NAME} v${SCRIPT_VERSION}</p>
            <p>Léon "Avic" Simmons</p>
        </div>
    </div>
</body>
</html>
EOF
}

# Generate plain text email body
generate_plain_email() {
    local status="$1"
    local success_count="$2"
    local failure_count="$3"
    local duration="$4"
    local hostname
    hostname=$(hostname)
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat << EOF
================================================================================
BACKUP REPORT - ${status^^}
================================================================================

Hostname:             ${hostname}
Timestamp:            ${timestamp}
Duration:             ${duration} seconds
Status:               ${status^^}

--------------------------------------------------------------------------------
STATISTICS
--------------------------------------------------------------------------------

Successful Operations: ${success_count}
Failed Operations:     ${failure_count}

--------------------------------------------------------------------------------

Log file: ${LOG_FILE}

Generated by ${SCRIPT_NAME} v${SCRIPT_VERSION}
Léon "Avic" Simmons

================================================================================
EOF
}

# Send email notification
send_email_notification() {
    local status="$1"
    local success_count="$2"
    local failure_count="$3"
    local duration="$4"

    # Check if we should send email for this status
    local should_send=false
    if [[ "${status}" == "success" ]] && [[ "${EMAIL_ON_SUCCESS}" == true ]]; then
        should_send=true
    elif [[ "${status}" == "failure" ]] && [[ "${EMAIL_ON_FAILURE}" == true ]]; then
        should_send=true
    fi

    if [[ "${should_send}" != true ]]; then
        log_debug "Email notification not configured for ${status} status"
        return 0
    fi

    # Check if email address is provided
    if [[ -z "${EMAIL_TO}" ]]; then
        log_warn "Email notification requested but no email address provided (use --email-to)"
        return 0
    fi

    # Check if mail command is available
    if ! command -v mail &> /dev/null && ! command -v sendmail &> /dev/null; then
        log_warn "Email notification requested but 'mail' command not available"
        log_warn "Install mailutils: sudo apt install mailutils"
        return 0
    fi

    local subject="Backup ${status^^} - $(hostname) - $(date '+%Y-%m-%d %H:%M')"
    local email_body
    local content_type="text/plain"

    # Generate email body based on HTML preference
    if [[ "${EMAIL_HTML}" == true ]]; then
        email_body=$(generate_html_email "${status}" "${success_count}" "${failure_count}" "${duration}")
        content_type="text/html"
        log_debug "Sending HTML email notification"
    else
        email_body=$(generate_plain_email "${status}" "${success_count}" "${failure_count}" "${duration}")
        log_debug "Sending plain text email notification"
    fi

    # Send email using mail command with proper headers
    if command -v mail &> /dev/null; then
        echo "${email_body}" | mail -s "${subject}" -a "Content-Type: ${content_type}; charset=UTF-8" "${EMAIL_TO}"
    else
        # Fallback to sendmail with manual headers
        {
            echo "To: ${EMAIL_TO}"
            echo "Subject: ${subject}"
            echo "Content-Type: ${content_type}; charset=UTF-8"
            echo "MIME-Version: 1.0"
            echo ""
            echo "${email_body}"
        } | sendmail -t
    fi

    if [[ $? -eq 0 ]]; then
        log_success "Email notification sent to ${EMAIL_TO}"
    else
        log_error "Failed to send email notification"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# SIGNAL HANDLERS
# -----------------------------------------------------------------------------
# These handlers ensure graceful cleanup when the script is interrupted
# -----------------------------------------------------------------------------

# Handle script interruption (Ctrl+C) or termination
cleanup() {
    local exit_code=$?
    log_warn "Backup interrupted! Cleaning up..."
    release_lock
    log_info "Cleanup complete. Check log file for details: ${LOG_FILE}"
    exit "${exit_code}"
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
# The main function orchestrates the entire backup process, calling each
# component function in the correct order with proper error handling.
# -----------------------------------------------------------------------------

main() {
    # Record start time for duration calculation
    local start_time
    start_time=$(date +%s)

    # Set up signal handlers for graceful interruption
    # SIGINT: Ctrl+C, SIGTERM: kill command
    trap cleanup SIGINT SIGTERM

    # Initialize logging
    setup_logging

    # Display startup banner
    log_info "=========================================="
    log_info "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    log_info "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "=========================================="

    # Parse any command-line arguments
    parse_arguments "$@"

    # Perform pre-flight checks
    log_info "Running pre-flight checks..."
    check_dependencies
    acquire_lock

    # Track success/failure counts
    local success_count=0
    local failure_count=0

    # -------------------------------------------------------------------------
    # PHASE 1: Archive Backups (rsync)
    # These backups preserve everything, even deleted files
    # -------------------------------------------------------------------------
    log_info "------------------------------------------"
    log_info "Phase 1: Archive Backups"
    log_info "------------------------------------------"

    # Archive each configured directory
    for dir in "${SOURCE_DIRS[@]}"; do
        if backup_archive_directory "${dir}"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
    done

    # Archive each configured individual file
    for file in "${SOURCE_FILES[@]}"; do
        if backup_archive_file "${file}"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
    done

    # -------------------------------------------------------------------------
    # PHASE 2: Sync Backups (unison)
    # These backups reflect current state, including deletions
    # -------------------------------------------------------------------------
    log_info "------------------------------------------"
    log_info "Phase 2: Sync Backups"
    log_info "------------------------------------------"

    # Sync each configured directory
    for dir in "${SOURCE_DIRS[@]}"; do
        if backup_sync_directory "${dir}"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
    done

    # -------------------------------------------------------------------------
    # PHASE 3: Mirror Backup
    # Create a backup of the backups for extra redundancy
    # -------------------------------------------------------------------------
    log_info "------------------------------------------"
    log_info "Phase 3: Mirror Backup"
    log_info "------------------------------------------"

    if backup_mirror; then
        ((success_count++))
    else
        ((failure_count++))
    fi

    # -------------------------------------------------------------------------
    # SUMMARY
    # -------------------------------------------------------------------------
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "=========================================="
    log_info "Backup Complete!"
    log_info "=========================================="
    log_info "Duration: ${duration} seconds"
    log_info "Successful operations: ${success_count}"

    if [[ ${failure_count} -gt 0 ]]; then
        log_warn "Failed operations: ${failure_count}"
    fi

    log_info "Log file: ${LOG_FILE}"

    # Send email notification if configured
    local backup_status="success"
    if [[ ${failure_count} -gt 0 ]]; then
        backup_status="failure"
    fi
    send_email_notification "${backup_status}" "${success_count}" "${failure_count}" "${duration}"

    # Clean up
    release_lock

    # Exit with error code if any operations failed
    if [[ ${failure_count} -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

# -----------------------------------------------------------------------------
# SCRIPT ENTRY POINT
# -----------------------------------------------------------------------------
# Only run main() if this script is being executed directly (not sourced)
# This allows the script to be sourced for testing individual functions
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
