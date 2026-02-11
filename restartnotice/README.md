# restartnotice
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A simple, well-documented shell script that sends an email notification whenever a server reboots, perfect for monitoring unexpected restarts or confirming scheduled maintenance.

## Features

- Automatic notifications -- emails you immediately when a server restarts
- Beautiful HTML emails -- rich, colorful table layout with important details at a glance (plain text option available)
- Detailed system info -- includes hostname, IP address, uptime, OS, and kernel version
- System logging -- logs all notification attempts to syslog for auditing
- Flexible setup -- use systemd (preferred) or crontab for triggering on boot

## Requirements

- A Linux/Unix system with bash
- A working mail transfer agent (MTA) such as:
  - [Postfix](http://www.postfix.org/)
  - [msmtp](https://marlam.de/msmtp/)
  - [sendmail](https://www.proofpoint.com/us/products/email-protection/open-source-email-solution)

### Gmail Users

If using Gmail, you will need to create an App Password instead of your regular account password:

1. Enable 2-Step Verification on your Google Account.
2. Go to [App Passwords](https://myaccount.google.com/apppasswords).
3. Generate a new App Password for "Mail" and use it in your MTA configuration.

> **Note:** Google deprecated "Less Secure Apps" access. App Passwords are now required.

## Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/Avicennasis/restartnotice.git
   cd restartnotice
   ```

2. **Configure the script:**

   Edit `restartnotice.sh` and update the `RECIPIENT_EMAIL` variable:

   ```bash
   RECIPIENT_EMAIL="your-email@example.com"
   ```

3. **Make the script executable:**

   ```bash
   chmod +x restartnotice.sh
   ```

4. **Test the script:**

   Run it manually to verify email delivery:

   ```bash
   ./restartnotice.sh
   ```

   To test plain text emails without HTML formatting:

   ```bash
   ./restartnotice.sh --html-off
   ```

## Usage

```bash
# Run manually
./restartnotice.sh

# Run with plain text email instead of HTML
./restartnotice.sh --html-off
```

### Example Email

When activated, you will receive a beautifully formatted HTML email with:

- A colorful gradient header
- A clean, organized table with system information
- Color-coded rows for easy reading
- Icons for quick visual reference
- Professional styling that works across email clients

**HTML Version (Default):**
The email includes a responsive table with purple gradient header, alternating row colors, and all the details formatted in a clean, professional layout.

**Plain Text Version** (with `--html-off` flag):

```
Server Reboot Notification
==========================

Server "webserver01" has restarted.

Reboot Details:
---------------
  Timestamp:    2026 Jan 03 00:15:30
  Hostname:     webserver01
  IP Address:   192.168.1.100
  Uptime:       up 1 minute
  OS:           Ubuntu 24.04 LTS
  Kernel:       6.8.0-generic
```

## Scheduling

### systemd

Systemd is the modern init system used by most Linux distributions and provides better logging, dependency management, and reliability.

1. **Create a systemd service file:**

   ```bash
   sudo nano /etc/systemd/system/restartnotice.service
   ```

2. **Add the following configuration** (adjust the path to match your installation):

   ```ini
   [Unit]
   Description=Server Reboot Notification Email
   After=network-online.target
   Wants=network-online.target

   [Service]
   Type=oneshot
   ExecStart=/path/to/restartnotice.sh
   User=root
   StandardOutput=journal
   StandardError=journal

   [Install]
   WantedBy=multi-user.target
   ```

   > **Note:** Replace `/path/to/restartnotice.sh` with the actual absolute path to your script.

3. **Enable and test the service:**

   ```bash
   # Reload systemd to recognize the new service
   sudo systemctl daemon-reload

   # Enable the service to run on boot
   sudo systemctl enable restartnotice.service

   # Test the service manually
   sudo systemctl start restartnotice.service

   # Check the service status and logs
   sudo systemctl status restartnotice.service
   sudo journalctl -u restartnotice.service
   ```

### Crontab

If your system does not use systemd or you prefer cron:

1. **Open your crontab:**

   ```bash
   crontab -e
   ```

2. **Add this line** (adjust the path to match your installation):

   ```
   @reboot /path/to/restartnotice.sh
   ```

3. **Verify the crontab entry:**

   ```bash
   crontab -l
   ```

## Troubleshooting

### General Issues

- **Email not sending?**
  - Test your MTA configuration: `echo "test" | mail -s "Test" your@email.com`
  - Check that the `mail` command is installed: `which mail`
  - Verify your SMTP settings (check `/etc/msmtprc` for msmtp, `/etc/postfix/main.cf` for Postfix)

- **Script execution issues?**
  - Verify the script is executable: `ls -la restartnotice.sh`
  - Check for syntax errors: `bash -n restartnotice.sh`
  - Run manually to see errors: `./restartnotice.sh`

### Systemd Troubleshooting

- **Check if the service is enabled:**
  ```bash
  sudo systemctl is-enabled restartnotice.service
  ```
  Should return `enabled`. If not, run: `sudo systemctl enable restartnotice.service`

- **View service status:**
  ```bash
  sudo systemctl status restartnotice.service
  ```
  Look for `Active: inactive (dead)` after the service runs, which is normal for a oneshot service.

- **Check service logs:**
  ```bash
  # View all logs for the service
  sudo journalctl -u restartnotice.service

  # View logs since last boot
  sudo journalctl -u restartnotice.service -b

  # Follow logs in real-time (useful during testing)
  sudo journalctl -u restartnotice.service -f

  # View logs with more detail
  sudo journalctl -u restartnotice.service -xe
  ```

- **Service won't start:**
  - Check the service file syntax: `sudo systemd-analyze verify /etc/systemd/system/restartnotice.service`
  - Ensure the script path is absolute (not relative) in the service file
  - Verify the script file exists: `ls -la /path/to/restartnotice.sh`
  - Check permissions: The script should be readable and executable by root

- **Service runs but no email arrives:**
  - Check the journal for mail errors: `sudo journalctl -u restartnotice.service -b`
  - Verify network is ready: The service waits for `network-online.target`, but some networks take longer
  - Try increasing the wait time by adding `ExecStartPre=/bin/sleep 10` to the service file
  - Check application logs: `grep restartnotice /var/log/syslog`

- **Test the service manually:**
  ```bash
  # Start the service manually (simulates a boot)
  sudo systemctl start restartnotice.service

  # Check if it ran successfully
  sudo systemctl status restartnotice.service

  # View any error output
  sudo journalctl -u restartnotice.service -n 50
  ```

- **Reload systemd after changes:**
  ```bash
  # Always reload after editing the service file
  sudo systemctl daemon-reload
  sudo systemctl restart restartnotice.service
  ```

### Crontab Troubleshooting

- **Verify crontab entry:**
  ```bash
  crontab -l | grep restartnotice
  ```

- **Check cron logs:**
  ```bash
  grep CRON /var/log/syslog | grep restartnotice
  ```

- **Permissions issue:**
  - Ensure the script has execute permissions: `chmod +x restartnotice.sh`
  - Use absolute paths in crontab entries, not relative paths

### Email Format Issues

- **HTML not rendering:**
  - Some email clients or security settings may strip HTML
  - Use the `--html-off` flag for plain text: Update your systemd service or crontab to include the flag
  - For systemd, change `ExecStart=/path/to/restartnotice.sh --html-off`

- **Check application logs:**
  ```bash
  # For systemd
  sudo journalctl -t restartnotice

  # For traditional syslog
  grep restartnotice /var/log/syslog
  ```

## Credits

**Author:** Leon "Avic" Simmons -- [GitHub](https://github.com/Avicennasis)
