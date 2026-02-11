#!/bin/bash
# =============================================================================
# restartnotice.sh - Server Reboot Notification Script
# =============================================================================
#
# DESCRIPTION:
#   This script sends an email notification when a server reboots, making it
#   easy to track unexpected restarts or confirm scheduled maintenance windows.
#   Designed to be triggered by systemd or cron's @reboot directive.
#
# AUTHOR:
#   Léon "Avic" Simmons (https://github.com/Avicennasis)
#
# LICENSE:
#   MIT License - See LICENSE file for details.
#
# USAGE:
#   1. Edit the configuration variables below (especially RECIPIENT_EMAIL).
#   2. Make the script executable: chmod +x restartnotice.sh
#   3. Set up with systemd (preferred) or crontab (see README.md)
#   4. Use --html-off flag to disable HTML formatting: ./restartnotice.sh --html-off
#
# REQUIREMENTS:
#   - A working mail transfer agent (MTA) such as Postfix, msmtp, or sendmail.
#   - For Gmail, use an App Password rather than your account password.
#     See: https://support.google.com/accounts/answer/185833
#
# =============================================================================

# -----------------------------------------------------------------------------
# COMMAND LINE ARGUMENTS
# -----------------------------------------------------------------------------
# Check if user wants plain text emails instead of HTML
USE_HTML=true
if [[ "$1" == "--html-off" ]]; then
    USE_HTML=false
fi

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
# The email address that will receive the reboot notification.
# Change this to your preferred email address.
RECIPIENT_EMAIL="USERNAME@gmail.com"

# The subject line for the notification email.
# You can customize this to suit your preferences or monitoring needs.
EMAIL_SUBJECT="System Restart Notification"

# -----------------------------------------------------------------------------
# SYSTEM INFORMATION GATHERING
# -----------------------------------------------------------------------------
# Get the system's hostname for identification in the email.
# This helps distinguish notifications when managing multiple servers.
HOSTNAME=$(hostname)

# Capture the current date and time in a human-readable format.
# Format: YYYY Mon DD HH:MM:SS (e.g., "2026 Jan 03 00:15:30")
TIMESTAMP=$(date '+%Y %b %d %H:%M:%S')

# Get the system's uptime information (time since boot).
# This helps confirm this is a fresh reboot and not a false trigger.
UPTIME=$(uptime -p 2>/dev/null || uptime)

# Retrieve the system's IP address for quick remote access reference.
# Uses 'hostname -I' which returns all IP addresses (works on most Linux distros).
# Falls back to 'N/A' if the command fails.
IP_ADDRESS=$(hostname -I 2>/dev/null | awk '{print $1}')
IP_ADDRESS=${IP_ADDRESS:-"N/A"}

# Get kernel version information for troubleshooting purposes.
# Useful when tracking if a reboot was due to a kernel update.
KERNEL_VERSION=$(uname -r)

# Get the operating system name and version.
# Reads from /etc/os-release if available, otherwise falls back to uname.
if [[ -f /etc/os-release ]]; then
    OS_INFO=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
else
    OS_INFO=$(uname -o)
fi

# -----------------------------------------------------------------------------
# EMAIL BODY CONSTRUCTION
# -----------------------------------------------------------------------------
# Compose a detailed, informative email body with relevant system information.
# Supports both HTML and plain text formats based on USE_HTML flag.

if [[ "${USE_HTML}" == "true" ]]; then
    # HTML formatted email with colorful table
    EMAIL_BODY=$(cat <<EOF
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
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
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 24px;
            font-weight: 600;
        }
        .content {
            padding: 30px;
        }
        .alert-message {
            background-color: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin-bottom: 20px;
            border-radius: 4px;
        }
        .alert-message strong {
            color: #856404;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            background-color: #ffffff;
        }
        th {
            background-color: #667eea;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        td {
            padding: 12px;
            border-bottom: 1px solid #e0e0e0;
        }
        tr:last-child td {
            border-bottom: none;
        }
        tr:nth-child(even) {
            background-color: #f8f9fa;
        }
        .label {
            font-weight: 600;
            color: #495057;
            width: 35%;
        }
        .value {
            color: #212529;
            font-family: 'Courier New', monospace;
        }
        .footer {
            background-color: #f8f9fa;
            padding: 20px 30px;
            font-size: 12px;
            color: #6c757d;
            border-top: 1px solid #e0e0e0;
        }
        .footer a {
            color: #667eea;
            text-decoration: none;
        }
        .footer a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔄 Server Reboot Notification</h1>
        </div>
        <div class="content">
            <div class="alert-message">
                <strong>Server "${HOSTNAME}" has restarted.</strong>
            </div>
            <table>
                <thead>
                    <tr>
                        <th colspan="2">Reboot Details</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td class="label">⏰ Timestamp</td>
                        <td class="value">${TIMESTAMP}</td>
                    </tr>
                    <tr>
                        <td class="label">🖥️ Hostname</td>
                        <td class="value">${HOSTNAME}</td>
                    </tr>
                    <tr>
                        <td class="label">🌐 IP Address</td>
                        <td class="value">${IP_ADDRESS}</td>
                    </tr>
                    <tr>
                        <td class="label">⏱️ Uptime</td>
                        <td class="value">${UPTIME}</td>
                    </tr>
                    <tr>
                        <td class="label">💿 Operating System</td>
                        <td class="value">${OS_INFO}</td>
                    </tr>
                    <tr>
                        <td class="label">⚙️ Kernel Version</td>
                        <td class="value">${KERNEL_VERSION}</td>
                    </tr>
                </tbody>
            </table>
            <p style="color: #6c757d; font-size: 14px;">
                This notification was automatically generated by restartnotice.sh
                upon system startup. If this restart was unexpected, please
                investigate the server logs (<code>/var/log/syslog</code> or <code>journalctl</code>).
            </p>
        </div>
        <div class="footer">
            Generated by <a href="https://github.com/Avicennasis/restartnotice">restartnotice</a> •
            Run with <code>--html-off</code> flag for plain text emails
        </div>
    </div>
</body>
</html>
EOF
)
else
    # Plain text email (original format)
    EMAIL_BODY=$(cat <<EOF
Server Reboot Notification
==========================

Server "${HOSTNAME}" has restarted.

Reboot Details:
---------------
  Timestamp:    ${TIMESTAMP}
  Hostname:     ${HOSTNAME}
  IP Address:   ${IP_ADDRESS}
  Uptime:       ${UPTIME}
  OS:           ${OS_INFO}
  Kernel:       ${KERNEL_VERSION}

This notification was automatically generated by restartnotice.sh
upon system startup. If this restart was unexpected, please
investigate the server logs (/var/log/syslog or journalctl).

---
https://github.com/Avicennasis/restartnotice
EOF
)
fi

# -----------------------------------------------------------------------------
# SEND NOTIFICATION EMAIL
# -----------------------------------------------------------------------------
# Send the email using the 'mail' command (provided by mailutils or similar).
# For HTML emails, we need to include content type headers.
if [[ "${USE_HTML}" == "true" ]]; then
    # Send HTML email with proper headers
    echo "${EMAIL_BODY}" | mail -s "${EMAIL_SUBJECT}" "${RECIPIENT_EMAIL}"
else
    # Send plain text email
    echo "${EMAIL_BODY}" | mail -s "${EMAIL_SUBJECT}" "${RECIPIENT_EMAIL}"
fi

# Capture the exit code of the mail command for logging purposes.
MAIL_EXIT_CODE=$?

# -----------------------------------------------------------------------------
# LOGGING
# -----------------------------------------------------------------------------
# Log the notification attempt to syslog for auditing and troubleshooting.
# Uses logger command to send messages to the system log.
if [[ ${MAIL_EXIT_CODE} -eq 0 ]]; then
    logger -t restartnotice "Reboot notification email sent successfully to ${RECIPIENT_EMAIL}"
else
    logger -t restartnotice "Failed to send reboot notification email (exit code: ${MAIL_EXIT_CODE})"
fi

# Exit with the same code as the mail command to indicate success/failure.
exit ${MAIL_EXIT_CODE}
