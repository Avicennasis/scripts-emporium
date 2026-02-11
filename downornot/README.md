# DownOrNot
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

A lightweight website uptime monitoring system that alerts you via email when your site goes down.

DownOrNot continuously monitors a website's availability, logs all check results for historical analysis, and includes a companion script to calculate your uptime percentage.

## Features

- Simple setup via interactive wizard that generates customized monitoring scripts
- Continuous monitoring with configurable check intervals (every few seconds)
- HTML email alerts with color-coded tables (plain text option available)
- Native systemd service files for reliable system startup
- Organized logging by date in `~/logs/<project>/YYYY/MM/`
- Uptime percentage reports from historical logs
- Signal handling for graceful shutdown

## Requirements

- Bash 4.0 or higher
- `curl` for HTTP requests
- `mail` for email notifications (e.g., `mailutils`, `sendmail`, or `postfix`)

## Installation

```bash
git clone https://github.com/Avicennasis/downornot.git
cd downornot
chmod +x setup.sh uptime.sh
```

## Usage

Run the setup script and follow the prompts to create a monitor:

```bash
./setup.sh
```

You will be asked for:
1. **Process name** - A unique identifier for this monitoring job
2. **URL** - The website URL to monitor (must include `http://` or `https://`)
3. **Email** - Email address for alert notifications

This generates a `<name>.generated.sh` script ready to run.

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--html-off` | Disable HTML email formatting (use plain text instead) | HTML enabled |

### Examples

**Run the generated monitor directly:**

```bash
./mysite.generated.sh
```

**Run in background:**

```bash
nohup ./mysite.generated.sh &
```

**Run with plain text emails:**

```bash
./mysite.generated.sh --html-off
```

**Check uptime interactively:**

```bash
./uptime.sh
```

**Check uptime for a specific project:**

```bash
./uptime.sh mysite
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CHECK_INTERVAL` | Seconds between checks | `3` |
| `FAILURE_THRESHOLD` | Consecutive failures before alerting | `4` |
| `REQUEST_TIMEOUT` | HTTP request timeout in seconds | `10` |

```bash
CHECK_INTERVAL=5 FAILURE_THRESHOLD=3 ./mysite.generated.sh
```

### Log Format

Logs are stored in `~/logs/<project>/YYYY/MM/YYYY-MM-DD.log`:

```
[OK] 2026-01-03 10:15:30 - https://example.com is up and running
[FAIL] 2026-01-03 10:15:33 - https://example.com IS DOWN! (Failure #1)
[INFO] 2026-01-03 10:00:00 - Monitoring started for https://example.com
```

## Scheduling

### systemd

The setup script generates systemd service files for automatic startup and management.

**Install and start the service:**

```bash
sudo cp mysite.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mysite.service
sudo systemctl start mysite.service
```

**Check service status:**

```bash
sudo systemctl status mysite.service
```

**View logs:**

```bash
sudo journalctl -u mysite.service -f
```

**Stop or restart the service:**

```bash
sudo systemctl stop mysite.service
sudo systemctl restart mysite.service
```

> **Note:** To use `--html-off` with systemd, edit the service file and modify the `ExecStart` line:
> ```ini
> ExecStart=/path/to/mysite.generated.sh --html-off
> ```

### Crontab

If systemd is not available or you prefer crontab:

```bash
crontab -e
```

Add this line:

```bash
@reboot /full/path/to/mysite.generated.sh
```

## Troubleshooting

### Service won't start

**Check service status and errors:**

```bash
sudo systemctl status mysite.service
sudo journalctl -u mysite.service -n 50
```

**Common issues:**

- **Permission denied**: Ensure the script is executable (`chmod +x mysite.generated.sh`)
- **Script not found**: Use absolute paths in the service file's `ExecStart` directive
- **User doesn't exist**: Verify the `User=` setting in the service file matches an existing user

### Service starts but stops immediately

**Check for script errors:**

```bash
sudo journalctl -u mysite.service -n 100
```

**Verify dependencies:**

- Ensure `curl` is installed: `which curl`
- Test mail functionality: `echo "test" | mail -s "Test" your@email.com`
- Check network connectivity: `curl -I https://example.com`

### Service running but no emails received

**Test email configuration:**

```bash
# Check if mail command works
echo "Test email" | mail -s "Test Subject" your@email.com

# Check system mail logs
sudo journalctl -u postfix -n 50  # for postfix
sudo tail -f /var/log/mail.log     # for other mail systems
```

**Common email issues:**

- Mail server not configured (install `mailutils` or `sendmail`)
- Firewall blocking SMTP ports
- Email marked as spam (check spam folder)
- HTML email not supported by mail server (use `--html-off` flag)

### Service not starting on boot

**Verify service is enabled:**

```bash
sudo systemctl is-enabled mysite.service
```

**Enable if not already:**

```bash
sudo systemctl enable mysite.service
```

**Check for failed units:**

```bash
sudo systemctl list-units --failed
```

### Viewing real-time logs

**Follow logs as they happen:**

```bash
# System logs (from journalctl)
sudo journalctl -u mysite.service -f

# Application logs (in ~/logs/)
tail -f ~/logs/mysite/$(date +%Y/%m/%Y-%m-%d).log
```

### Reloading after configuration changes

**After modifying the service file:**

```bash
sudo systemctl daemon-reload
sudo systemctl restart mysite.service
```

**After modifying the monitoring script:**

```bash
sudo systemctl restart mysite.service
```

### Checking system resource usage

**View CPU and memory usage:**

```bash
sudo systemctl status mysite.service
```

**Detailed resource info:**

```bash
ps aux | grep mysite.generated.sh
```

### Removing the service

**Stop and disable:**

```bash
sudo systemctl stop mysite.service
sudo systemctl disable mysite.service
sudo rm /etc/systemd/system/mysite.service
sudo systemctl daemon-reload
```

## Credits

**Author:** Léon "Avic" Simmons — [GitHub](https://github.com/Avicennasis)
