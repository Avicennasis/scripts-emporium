#!/bin/bash
# ==============================================================================
# TrafficCam - Traffic Camera Snapshot Email Service
# ==============================================================================
# Description: Downloads snapshot images from a traffic camera at regular
#              intervals and emails them to a specified recipient.
#
# Author:      Léon "Avic" Simmons (@Avicennasis)
# License:     MIT License
# Repository:  https://github.com/Avicennasis/trafficcam
# Updated:     2026-01-23
#
# Usage:       ./trafficcam.sh [options]
#              Run without options for default behavior (10 images, 60s interval)
#
# Dependencies:
#   - curl:    For downloading camera images
#   - mpack:   For sending email attachments
#   - ssmtp:   Must be configured for outbound email
# ==============================================================================

# ------------------------------------------------------------------------------
# CONFIGURATION - Modify these variables to customize behavior
# ------------------------------------------------------------------------------

# HTML email format flag (can be disabled with --html-off)
USE_HTML_EMAIL=true

# Number of images to capture and send
readonly IMAGE_COUNT="${TRAFFICCAM_COUNT:-10}"

# Interval between captures in seconds (default: 60 = 1 minute)
readonly CAPTURE_INTERVAL="${TRAFFICCAM_INTERVAL:-60}"

# URL of the traffic camera image
readonly CAMERA_URL="${TRAFFICCAM_URL:-http://link.to/camimage.jpg}"

# Email recipient address
readonly EMAIL_RECIPIENT="${TRAFFICCAM_EMAIL:-USERNAME@gmail.com}"

# Email subject line
readonly EMAIL_SUBJECT="${TRAFFICCAM_SUBJECT:-TrafficCam}"

# Temporary directory for storing downloaded images
readonly TEMP_DIR="${TRAFFICCAM_TEMP:-${HOME}/TEMP}"

# Temporary file path for the downloaded image
readonly IMAGE_FILE="${TEMP_DIR}/cam.jpg"

# Temporary file for HTML email body
readonly HTML_FILE="${TEMP_DIR}/email_body.html"

# Maximum retry attempts for failed downloads
readonly MAX_RETRIES=3

# Delay between retry attempts in seconds
readonly RETRY_DELAY=5

# ------------------------------------------------------------------------------
# HELPER FUNCTIONS
# ------------------------------------------------------------------------------

# Prints a timestamped log message to stdout
# Arguments:
#   $1 - Log level (INFO, WARN, ERROR, SUCCESS)
#   $2 - Message to log
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}"
}

# Verifies that all required dependencies are installed and available
# Exits with error code 1 if any dependency is missing
check_dependencies() {
    local missing_deps=()

    # Check for curl - used to download images from the camera URL
    if ! command -v curl &>/dev/null; then
        missing_deps+=("curl")
    fi

    # Check for mpack - used to send email with image attachment
    if ! command -v mpack &>/dev/null; then
        missing_deps+=("mpack")
    fi

    # If any dependencies are missing, report and exit
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        log "ERROR" "Please install the missing packages and try again."
        exit 1
    fi

    log "INFO" "All dependencies verified."
}

# Creates the temporary directory if it doesn't already exist
# This directory is used to store downloaded images before emailing
setup_temp_directory() {
    if [[ ! -d "${TEMP_DIR}" ]]; then
        log "INFO" "Temporary directory not found. Creating: ${TEMP_DIR}"
        mkdir -p "${TEMP_DIR}"

        # Verify the directory was created successfully
        if [[ ! -d "${TEMP_DIR}" ]]; then
            log "ERROR" "Failed to create temporary directory: ${TEMP_DIR}"
            exit 1
        fi

        log "SUCCESS" "Temporary directory created successfully."
    else
        log "INFO" "Using existing temporary directory: ${TEMP_DIR}"
    fi
}

# Downloads an image from the camera URL with retry logic
# Returns:
#   0 - Success (image downloaded and has content)
#   1 - Failure (download failed or empty file after all retries)
download_image() {
    local attempt=1

    while [[ ${attempt} -le ${MAX_RETRIES} ]]; do
        log "INFO" "Downloading image (attempt ${attempt}/${MAX_RETRIES})..."

        # Use curl to download the image
        # -s: Silent mode (no progress bar)
        # -S: Show errors if they occur
        # -f: Fail silently on HTTP errors (no output on 404, etc.)
        # -L: Follow redirects
        # -o: Output to specified file
        if curl -sSfL -o "${IMAGE_FILE}" "${CAMERA_URL}" 2>/dev/null; then
            # Verify the downloaded file has content
            if [[ -s "${IMAGE_FILE}" ]]; then
                log "SUCCESS" "Image downloaded successfully."
                return 0
            else
                log "WARN" "Downloaded file is empty."
            fi
        else
            log "WARN" "Download failed (HTTP error or network issue)."
        fi

        # Clean up any partial/empty file before retry
        [[ -f "${IMAGE_FILE}" ]] && rm -f "${IMAGE_FILE}"

        # If we haven't exhausted retries, wait before trying again
        if [[ ${attempt} -lt ${MAX_RETRIES} ]]; then
            log "INFO" "Waiting ${RETRY_DELAY} seconds before retry..."
            sleep "${RETRY_DELAY}"
        fi

        ((attempt++))
    done

    log "ERROR" "Failed to download image after ${MAX_RETRIES} attempts."
    return 1
}

# Sends the downloaded image as an email attachment
# Arguments:
#   $1 - Image number
#   $2 - Total images
# Returns:
#   0 - Email sent successfully
#   1 - Failed to send email
send_email() {
    local img_num="$1"
    local total="$2"
    log "INFO" "Sending email to ${EMAIL_RECIPIENT}..."

    if [[ "${USE_HTML_EMAIL}" == true ]]; then
        # Generate HTML email body
        generate_html_body "${img_num}" "${total}"

        # Send email with HTML body and image attachment
        # mpack -s: Subject line for the email
        # First file is treated as the body (HTML)
        # Subsequent files are attachments
        if mpack -s "${EMAIL_SUBJECT}" "${HTML_FILE}" "${IMAGE_FILE}" "${EMAIL_RECIPIENT}" 2>/dev/null; then
            log "SUCCESS" "Email sent successfully! (HTML format)"
            return 0
        else
            log "ERROR" "Failed to send email."
            return 1
        fi
    else
        # Send plain text email with attachment only
        # mpack sends the file as a MIME attachment
        # -s: Subject line for the email
        if mpack -s "${EMAIL_SUBJECT}" "${IMAGE_FILE}" "${EMAIL_RECIPIENT}" 2>/dev/null; then
            log "SUCCESS" "Email sent successfully! (Plain text)"
            return 0
        else
            log "ERROR" "Failed to send email."
            return 1
        fi
    fi
}

# Generates HTML email body with styled table
# Arguments:
#   $1 - Image number
#   $2 - Total images
generate_html_body() {
    local img_num="$1"
    local total="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat > "${HTML_FILE}" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background-color: #f5f5f5;
            margin: 0;
            padding: 20px;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            background-color: #ffffff;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #ffffff;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 28px;
            font-weight: 600;
        }
        .content {
            padding: 30px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            background-color: #ffffff;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        th {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #ffffff;
            padding: 15px;
            text-align: left;
            font-weight: 600;
            font-size: 14px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        td {
            padding: 15px;
            border-bottom: 1px solid #e0e0e0;
            color: #333333;
            font-size: 14px;
        }
        tr:last-child td {
            border-bottom: none;
        }
        tr:hover {
            background-color: #f8f9fa;
        }
        .label {
            font-weight: 600;
            color: #667eea;
        }
        .footer {
            background-color: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #666666;
            font-size: 12px;
            border-top: 1px solid #e0e0e0;
        }
        .badge {
            display: inline-block;
            padding: 4px 12px;
            background-color: #667eea;
            color: #ffffff;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📸 TrafficCam Snapshot</h1>
        </div>
        <div class="content">
            <p>Your traffic camera snapshot is ready! See the attached image for current conditions.</p>

            <table>
                <tr>
                    <th colspan="2">Snapshot Information</th>
                </tr>
                <tr>
                    <td class="label">Capture Time</td>
                    <td>${timestamp}</td>
                </tr>
                <tr>
                    <td class="label">Image Number</td>
                    <td><span class="badge">${img_num} of ${total}</span></td>
                </tr>
                <tr>
                    <td class="label">Camera URL</td>
                    <td style="word-break: break-all;">${CAMERA_URL}</td>
                </tr>
                <tr>
                    <td class="label">Status</td>
                    <td style="color: #10b981; font-weight: 600;">✓ Successfully Captured</td>
                </tr>
            </table>
        </div>
        <div class="footer">
            TrafficCam by Léon "Avic" Simmons | Automated Traffic Camera Monitoring
        </div>
    </div>
</body>
</html>
EOF
}

# Removes the temporary image file after processing
cleanup() {
    if [[ -f "${IMAGE_FILE}" ]]; then
        rm -f "${IMAGE_FILE}"
        log "INFO" "Cleaned up temporary image file."
    fi

    if [[ -f "${HTML_FILE}" ]]; then
        rm -f "${HTML_FILE}"
    fi
}

# Displays script usage information
show_usage() {
    cat <<EOF
TrafficCam - Traffic Camera Snapshot Email Service

Usage: ./trafficcam.sh [options]

Options:
  --html-off           Disable HTML email formatting (send plain text only)
  -h, --help           Show this help message

Environment Variables (optional configuration):
  TRAFFICCAM_COUNT     Number of images to capture (default: 10)
  TRAFFICCAM_INTERVAL  Seconds between captures (default: 60)
  TRAFFICCAM_URL       Camera image URL (default: http://link.to/camimage.jpg)
  TRAFFICCAM_EMAIL     Recipient email address (default: USERNAME@gmail.com)
  TRAFFICCAM_SUBJECT   Email subject line (default: TrafficCam)
  TRAFFICCAM_TEMP      Temporary directory path (default: \$HOME/TEMP)

Examples:
  # Run with defaults (HTML email enabled)
  ./trafficcam.sh

  # Disable HTML email formatting
  ./trafficcam.sh --html-off

  # Capture 5 images every 30 seconds
  TRAFFICCAM_COUNT=5 TRAFFICCAM_INTERVAL=30 ./trafficcam.sh

  # Use a custom camera URL and email
  TRAFFICCAM_URL="http://camera.example.com/snapshot.jpg" \\
  TRAFFICCAM_EMAIL="user@example.com" \\
  ./trafficcam.sh

EOF
}

# ------------------------------------------------------------------------------
# MAIN EXECUTION
# ------------------------------------------------------------------------------

main() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --html-off)
                USE_HTML_EMAIL=false
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Display startup banner
    log "INFO" "============================================"
    log "INFO" "TrafficCam - Starting capture session"
    log "INFO" "============================================"
    log "INFO" "Configuration:"
    log "INFO" "  - Images to capture: ${IMAGE_COUNT}"
    log "INFO" "  - Capture interval:  ${CAPTURE_INTERVAL} seconds"
    log "INFO" "  - Camera URL:        ${CAMERA_URL}"
    log "INFO" "  - Email recipient:   ${EMAIL_RECIPIENT}"
    log "INFO" "  - Email format:      $([ "${USE_HTML_EMAIL}" == true ] && echo "HTML" || echo "Plain text")"
    log "INFO" "  - Temp directory:    ${TEMP_DIR}"
    log "INFO" "============================================"

    # Verify all dependencies are available
    check_dependencies

    # Create temporary directory if needed
    setup_temp_directory

    # Track success/failure statistics
    local success_count=0
    local failure_count=0

    # Main capture loop
    for ((i = 1; i <= IMAGE_COUNT; i++)); do
        log "INFO" "--------------------------------------------"
        log "INFO" "Processing image ${i} of ${IMAGE_COUNT}"
        log "INFO" "--------------------------------------------"

        # Attempt to download the camera image
        if download_image; then
            # If download succeeded, send via email
            if send_email "${i}" "${IMAGE_COUNT}"; then
                ((success_count++))
            else
                ((failure_count++))
            fi
        else
            ((failure_count++))
        fi

        # Always clean up the temporary file
        cleanup

        # Wait before the next capture (skip wait on last iteration)
        if [[ ${i} -lt ${IMAGE_COUNT} ]]; then
            log "INFO" "Waiting ${CAPTURE_INTERVAL} seconds until next capture..."
            sleep "${CAPTURE_INTERVAL}"
        fi
    done

    # Display session summary
    log "INFO" "============================================"
    log "INFO" "TrafficCam - Session Complete"
    log "INFO" "============================================"
    log "INFO" "Results:"
    log "INFO" "  - Successful: ${success_count}"
    log "INFO" "  - Failed:     ${failure_count}"
    log "INFO" "  - Total:      ${IMAGE_COUNT}"
    log "INFO" "============================================"

    # Exit with error code if any failures occurred
    if [[ ${failure_count} -gt 0 ]]; then
        exit 1
    fi
}

# Run the main function, passing all command-line arguments
main "$@"
