# Backup Script
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A robust, modern backup utility for Linux and macOS that creates both archival (full history) and incremental (synchronized) backups of your important files and directories.

Originally created in 2015, completely rewritten in 2026 with modern best practices.

## Features

- Archive backups: preserves complete file history using `rsync` (deletions from source do not affect backups)
- Sync backups: bidirectional synchronization using `unison` (mirrors current state including deletions)
- Mirror backups: creates a backup of your backups for extra redundancy
- Color-coded output: easy-to-read status messages with distinct colors
- Comprehensive logging: timestamped logs saved to `~/.logs/backup/`
- Safe execution: lock file prevents concurrent runs; graceful interrupt handling
- Configurable source directories, destinations, and exclusion patterns
- Dry-run mode: preview what would happen without making changes
- Email notifications with HTML formatting (or plain text)

## Requirements

- Bash 4.0 or later
- `rsync` -- for archive backups
- `unison` -- for bidirectional synchronization
- `mailutils` or `mailx` (optional) -- for email notifications

```bash
# Ubuntu/Debian
sudo apt install rsync unison

# Fedora/RHEL
sudo dnf install rsync unison

# macOS (Homebrew)
brew install rsync unison
```

For email notifications:

```bash
# Ubuntu/Debian
sudo apt install mailutils

# Fedora/RHEL
sudo dnf install mailx
```

## Installation

Clone the repository and make the script executable:

```bash
chmod +x backup.sh
```

## Usage

```bash
# Run backup with default settings
./backup.sh

# Preview what would be backed up (dry-run)
./backup.sh --dry-run

# Run with verbose debugging output
./backup.sh --verbose

# Run silently (only show errors)
./backup.sh --quiet
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--help`, `-h` | Show help message and exit | -- |
| `--dry-run`, `-n` | Perform a trial run with no changes made | off |
| `--verbose`, `-v` | Enable verbose output for debugging | off |
| `--quiet`, `-q` | Suppress non-error output | off |
| `--email-on-success` | Send email notification on successful backup | off |
| `--email-on-failure` | Send email notification on failed backup | off |
| `--email-always` | Send email notification regardless of outcome | off |
| `--email-to <address>` | Email address to send notifications to | -- |
| `--html-off` | Disable HTML formatting in email (use plain text) | off |

### Examples

Send email only on failure:

```bash
./backup.sh --email-on-failure --email-to admin@example.com
```

Send email only on success:

```bash
./backup.sh --email-on-success --email-to admin@example.com
```

Send email always (success or failure):

```bash
./backup.sh --email-always --email-to admin@example.com
```

Use plain text instead of HTML email:

```bash
./backup.sh --email-always --email-to admin@example.com --html-off
```

## Configuration

Edit the `CONFIGURATION` section in `backup.sh` to customize your backup setup:

```bash
# Directories to back up (relative to home directory)
readonly SOURCE_DIRS=(
    "Downloads"
    "Documents"
    "scripts"
    "projects"
)

# Individual files to back up
readonly SOURCE_FILES=(
    ".bash_history"
    ".bashrc"
    ".profile"
)

# Backup destination base path
readonly BACKUP_BASE="/mnt/backup"

# Patterns to exclude from backups
readonly EXCLUDE_PATTERNS=(
    ".Trash-*"
    ".cache"
    "node_modules"
)
```

### Backup structure

The script creates the following directory structure:

```
/mnt/backup/
├── backup-archive/     # Full history preserved (rsync)
│   ├── Downloads/
│   ├── Documents/
│   ├── bash_history.txt
│   └── ...
├── backup-sync/        # Living sync (unison)
│   ├── Downloads/
│   ├── Documents/
│   └── ...
└── (backed up to external drive as mirror)
```

### Email notification features

By default, HTML emails include:

- Modern, responsive design with gradient headers
- Color-coded status indicators (green for success, red for failure)
- Statistics cards showing successful vs failed operations
- Detailed summary table with hostname, timestamp, duration
- Professional styling optimized for all email clients

Use `--html-off` if you prefer plain text emails or if your email client does not support HTML.

## Scheduling

### systemd

systemd timers provide better logging, dependency management, and error handling compared to cron.

#### Create the service file

Create `/etc/systemd/system/backup.service`:

```ini
[Unit]
Description=Automated Backup Script
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=YOUR_USERNAME
ExecStart=/home/YOUR_USERNAME/backup/backup.sh --quiet --email-on-failure --email-to your@email.com
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

> **Note:** Replace `YOUR_USERNAME` with your actual username and update the paths and email settings.

#### Create the timer file

Create `/etc/systemd/system/backup.timer`:

```ini
[Unit]
Description=Run backup script daily
Requires=backup.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
```

Schedule options:

| Setting | Description |
|---------|-------------|
| `OnCalendar=daily` | Every day at midnight |
| `OnCalendar=02:00` | Every day at 2:00 AM |
| `OnCalendar=*-*-* 04:00:00` | Every day at 4:00 AM |
| `OnCalendar=Mon,Wed,Fri 02:00` | Monday, Wednesday, Friday at 2:00 AM |
| `OnCalendar=weekly` | Once a week |
| `Persistent=true` | Runs immediately if system was off during scheduled time |
| `RandomizedDelaySec=15m` | Adds random 0-15 minute delay to reduce system load spikes |

#### Enable and start the timer

```bash
# Reload systemd to recognize new files
sudo systemctl daemon-reload

# Enable the timer to start on boot
sudo systemctl enable backup.timer

# Start the timer now
sudo systemctl start backup.timer

# Check timer status
sudo systemctl status backup.timer

# List all timers
systemctl list-timers backup.timer
```

### Crontab

If you do not have systemd or prefer cron, you can use crontab.

#### Edit your crontab

```bash
crontab -e
```

#### Add backup schedule

```bash
# Run backup daily at 2:00 AM with email notifications on failure
0 2 * * * /home/YOUR_USERNAME/backup/backup.sh --quiet --email-on-failure --email-to your@email.com

# Run backup every 6 hours
0 */6 * * * /home/YOUR_USERNAME/backup/backup.sh --quiet --email-on-failure --email-to your@email.com

# Run backup Monday, Wednesday, Friday at 3:00 AM
0 3 * * 1,3,5 /home/YOUR_USERNAME/backup/backup.sh --quiet --email-on-failure --email-to your@email.com

# Run backup on the 1st and 15th of each month at 1:00 AM
0 1 1,15 * * /home/YOUR_USERNAME/backup/backup.sh --quiet --email-on-failure --email-to your@email.com
```

Cron schedule format:

```
* * * * * command to execute
│ │ │ │ │
│ │ │ │ └─── Day of week (0-7, Sunday=0 or 7)
│ │ │ └───── Month (1-12)
│ │ └─────── Day of month (1-31)
│ └───────── Hour (0-23)
└─────────── Minute (0-59)
```

Special shortcuts:

| Shortcut | Description |
|----------|-------------|
| `@reboot` | Run once at startup |
| `@daily` or `@midnight` | Run once a day (00:00) |
| `@weekly` | Run once a week (Sunday 00:00) |
| `@monthly` | Run once a month (1st at 00:00) |
| `@hourly` | Run once an hour |

## Troubleshooting

### systemd issues

Check if timer is active:

```bash
systemctl list-timers backup.timer
```

View service logs:

```bash
# Recent logs
journalctl -u backup.service -n 50

# Follow logs in real-time
journalctl -u backup.service -f

# Logs from today
journalctl -u backup.service --since today

# Logs from specific date
journalctl -u backup.service --since "2026-01-15" --until "2026-01-16"
```

Manually trigger backup:

```bash
sudo systemctl start backup.service
```

Check for errors:

```bash
systemctl status backup.service
systemctl status backup.timer
```

Common systemd issues:

| Issue | Solution |
|-------|----------|
| Timer does not run | Check `systemctl status backup.timer` and ensure it is enabled with `systemctl enable backup.timer` |
| Permission denied | Ensure `User=` in service file matches file owner and paths are correct |
| Script not found | Verify `ExecStart=` path is absolute and script has execute permissions (`chmod +x backup.sh`) |
| Backup runs but fails | Check logs with `journalctl -u backup.service` and verify dependencies are installed |
| Timer stuck in failed state | Reset with `sudo systemctl reset-failed backup.service` then restart timer |

### Crontab issues

View current crontab:

```bash
crontab -l
```

Check if cron daemon is running:

```bash
# For most Linux systems
sudo systemctl status cron

# For some systems
sudo systemctl status crond
```

View cron logs:

```bash
# Ubuntu/Debian
grep CRON /var/log/syslog

# Fedora/RHEL/CentOS
grep CRON /var/log/cron

# Recent cron activity
journalctl -u cron --since today
```

Test cron entry:

```bash
# Set a test to run in 2 minutes
# If current time is 14:30, set for 14:32
32 14 * * * /home/YOUR_USERNAME/backup/backup.sh --dry-run
```

Common crontab issues:

| Issue | Solution |
|-------|----------|
| Cron job does not run | Verify cron daemon is running: `sudo systemctl status cron` or `crond` |
| Script not found | Use absolute paths for both script and executables (no relative paths like `~/`) |
| PATH issues | Add `PATH=/usr/local/bin:/usr/bin:/bin` at the top of crontab |
| No error output | Redirect output: `... 2>&1 \| tee -a /home/USER/backup-cron.log` |
| Permission denied | Ensure script has execute permissions: `chmod +x backup.sh` |
| Email not working | Install mail utilities: `sudo apt install mailutils` or `sudo dnf install mailx` |
| Environment variables missing | Set them explicitly in crontab or source profile: `. $HOME/.profile; /path/to/backup.sh` |

## Credits

**Author:** Leon "Avic" Simmons -- [GitHub](https://github.com/Avicennasis)
