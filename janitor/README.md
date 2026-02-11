# Janitor
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A robust shell script that automates the cleanup of temporary files in a specified directory, helping maintain disk space by deleting files older than a configurable number of days.

Janitor keeps detailed logs of all operations, including a running total of bytes deleted and monthly records of individual file deletions.

## Features

- Automated cleanup of files older than a configurable retention period (default: 30 days)
- Running total of bytes deleted maintained in `~/logs/janitor/tempsizeinbytes.txt`
- Monthly deletion logs in `~/logs/janitor/YYYY/MM/deleted.txt`
- Safety checks to ensure the target directory exists and is not empty before attempting deletion
- Console output of status and size information during execution
- Optional HTML or plain text email reports

## Requirements

- Bash
- `find` for locating files by age
- `mail` for email notifications (e.g., `mailutils` or `sendmail`; only required if using `--email`)

## Installation

1. Clone this repository or download `janitor.sh`.

2. Edit `janitor.sh` and configure the `TARGET_DIR` variable:

   ```bash
   TARGET_DIR="/path/to/your/temp/dir"
   ```

3. Make the script executable:

   ```bash
   chmod +x janitor.sh
   ```

## Usage

```bash
./janitor.sh [OPTIONS]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--email EMAIL` | Send a cleanup report to the specified email address | - |
| `--html-off` | Send a plain text email instead of HTML (requires `--email`) | HTML enabled |

### Examples

**Run a basic cleanup:**

```bash
./janitor.sh
```

**Run with HTML email notification:**

```bash
./janitor.sh --email admin@example.com
```

**Run with plain text email notification:**

```bash
./janitor.sh --email admin@example.com --html-off
```

## Configuration

You can customize the following variables at the top of `janitor.sh`:

| Variable | Description | Default |
|----------|-------------|---------|
| `TARGET_DIR` | The directory to clean | `/cygdrive/d/Mil-Main/TEMP` |
| `RETENTION_DAYS` | Files older than this number of days will be deleted | `30` |
| `LOG_BASE_DIR` | Where logs will be stored | `~/logs/janitor` |

## Scheduling

### systemd

systemd timers provide a modern, reliable way to schedule tasks on Linux systems.

**1. Create the service file** at `/etc/systemd/system/janitor.service`:

```ini
[Unit]
Description=Janitor cleanup service
After=network.target

[Service]
Type=oneshot
User=YOUR_USERNAME
ExecStart=/full/path/to/janitor.sh --email admin@example.com
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

> **Note:** Replace `YOUR_USERNAME` with your actual username and update the path to `janitor.sh`.

**2. Create the timer file** at `/etc/systemd/system/janitor.timer`:

```ini
[Unit]
Description=Run janitor cleanup daily
Requires=janitor.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
```

**Timer options:**

- `OnCalendar=daily` - Run once per day at midnight
- `OnCalendar=weekly` - Run once per week
- `OnCalendar=*-*-* 02:00:00` - Run daily at 2 AM
- `OnCalendar=Mon,Wed,Fri *-*-* 03:00:00` - Run Mon/Wed/Fri at 3 AM
- `RandomizedDelaySec=1h` - Adds random delay up to 1 hour (optional, helps distribute system load)
- `Persistent=true` - Run immediately if system was off during scheduled time

**3. Enable and start the timer:**

```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Enable timer to start on boot
sudo systemctl enable janitor.timer

# Start the timer now
sudo systemctl start janitor.timer

# Check timer status
sudo systemctl status janitor.timer

# List all timers to verify
systemctl list-timers janitor.timer
```

**4. Manually trigger the service (optional):**

```bash
# Run the service immediately for testing
sudo systemctl start janitor.service

# View the logs
sudo journalctl -u janitor.service
```

### Crontab

If you prefer crontab or don't have systemd available, you can use cron to schedule the script.

**1. Edit your crontab:**

```bash
crontab -e
```

**2. Add a cron entry:**

```cron
# Run janitor daily at 2 AM
0 2 * * * /full/path/to/janitor.sh --email admin@example.com >> ~/logs/janitor/cron.log 2>&1

# Run janitor every Sunday at 3 AM
0 3 * * 0 /full/path/to/janitor.sh --email admin@example.com >> ~/logs/janitor/cron.log 2>&1

# Run janitor on the 1st of every month at 1 AM
0 1 1 * * /full/path/to/janitor.sh --email admin@example.com >> ~/logs/janitor/cron.log 2>&1
```

**Cron format:** `minute hour day month weekday command`

- `0 2 * * *` - 2 AM every day
- `30 14 * * *` - 2:30 PM every day
- `0 0 * * 0` - Midnight every Sunday
- `0 3 1 * *` - 3 AM on the 1st of every month

> **Note:** Always use absolute paths in crontab entries.

**3. Verify the crontab entry:**

```bash
crontab -l
```

## Troubleshooting

### systemd: Timer not running

```bash
# Check if timer is active
systemctl is-active janitor.timer

# Check if timer is enabled
systemctl is-enabled janitor.timer

# View timer details and next scheduled run
systemctl list-timers janitor.timer

# Check timer logs
sudo journalctl -u janitor.timer
```

### systemd: Service failing

```bash
# Check service status
sudo systemctl status janitor.service

# View recent service logs
sudo journalctl -u janitor.service -n 50

# View logs with timestamps
sudo journalctl -u janitor.service --since "1 hour ago"

# Follow logs in real-time
sudo journalctl -u janitor.service -f
```

### Common systemd issues

1. **Permission denied**: Ensure the script is executable (`chmod +x janitor.sh`) and the `User=` in the service file is correct.

2. **Path not found**: Use absolute paths in the service file's `ExecStart=` directive.

3. **Timer not triggering**: Make sure you started the `.timer` file, not the `.service` file:

   ```bash
   sudo systemctl start janitor.timer  # Correct
   sudo systemctl start janitor.service # This only runs it once
   ```

4. **Changes not taking effect**: Always run `sudo systemctl daemon-reload` after editing service or timer files.

5. **Email not sending**: Ensure you have `mailutils` or `sendmail` installed:

   ```bash
   sudo apt-get install mailutils  # Debian/Ubuntu
   sudo yum install mailx          # RHEL/CentOS
   ```

### Crontab: Job not running

```bash
# Check if cron daemon is running
sudo systemctl status cron    # Debian/Ubuntu
sudo systemctl status crond   # RHEL/CentOS

# Start cron if it's not running
sudo systemctl start cron     # Debian/Ubuntu
sudo systemctl start crond    # RHEL/CentOS

# View cron logs
grep CRON /var/log/syslog     # Debian/Ubuntu
sudo tail -f /var/log/cron    # RHEL/CentOS
```

### Common crontab issues

1. **Script not found**: Always use absolute paths in cron entries. Cron does not use your user's PATH.

   ```bash
   # Wrong
   0 2 * * * janitor.sh

   # Correct
   0 2 * * * /home/user/scripts/janitor.sh
   ```

2. **Environment variables**: Cron runs with a minimal environment. Set required variables in the crontab:

   ```cron
   PATH=/usr/local/bin:/usr/bin:/bin
   HOME=/home/user

   0 2 * * * /home/user/janitor.sh
   ```

3. **No output/errors**: Redirect output to a log file to debug:

   ```cron
   0 2 * * * /path/to/janitor.sh >> /path/to/logfile.log 2>&1
   ```

4. **Permission denied**: Ensure the script has execute permissions:

   ```bash
   chmod +x /path/to/janitor.sh
   ```

5. **Email not working**: Install a mail transfer agent:

   ```bash
   sudo apt-get install mailutils  # Debian/Ubuntu
   ```

   Or disable cron email notifications:

   ```cron
   MAILTO=""
   0 2 * * * /path/to/janitor.sh
   ```

6. **Testing cron timing**: Use a tool like [crontab.guru](https://crontab.guru/) to verify your cron schedule syntax.

## Credits

**Author:** Léon "Avic" Simmons — [GitHub](https://github.com/Avicennasis)
