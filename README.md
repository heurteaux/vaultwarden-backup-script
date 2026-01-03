# Generic Backup Script Template

A flexible, POSIX-compliant backup script template using BorgBackup with email notifications. Perfect for creating automated backups of any service or data.

## Features

- Secure encrypted backups using BorgBackup
- Email notifications with detailed logs
- Automatic pruning with configurable retention policies
- Pre and post-backup operation hooks
- HTML email reports
- POSIX compliant

## Prerequisites

The following tools must be installed on your system:

- `borg` (BorgBackup)
- `msmtp` (for email sending)
- `envsubst` (usually part of `gettext`)
- Standard Unix utilities: `base64`, `grep`, `hostname`, `date`, `fold`, `cat`

### Installation on Debian/Ubuntu

```sh
sudo apt install borgbackup msmtp gettext-base
```

## Setup

### 1. Clone the repository

```sh
git clone https://github.com/heurteaux/generic-backup-script.git
cd generic-backup-script
```

### 2. Configure environment variables

Copy the example configuration and edit it:

```sh
cp .env.example .env
nano .env
```

### 3. Configure msmtp

Create or edit `~/.msmtprc` with your email server settings:

```
# Set default values for all following accounts.
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile ~/.msmtp.log

# Default account
account default
host smtp.example.com
port 587
tls_starttls on # if service is using starttls
from your-email@example.com
user your-email@example.com
password your-password
```

Make sure to secure the file:

```sh
chmod 600 ~/.msmtprc
```

### 4. Initialize BorgBackup repository

```sh
borg init --encryption=repokey /path/to/your/repo
```

### 5. Customize the script

Edit the `run_pre_backup_operations()` and `run_post_backup_operations()` functions in `backup.sh` to add your custom backup logic.

**Example for database backup:**

```sh
run_pre_backup_operations() {
    # Dump database
    docker exec -t myapp_db pg_dumpall --clean --if-exists --username="$DB_USERNAME" > "$UPLOAD_LOCATION"/database-backup/database.sql
}
```

**Example for stopping/starting services:**

```sh
run_pre_backup_operations() {
    # Stop service for consistent backup
    docker compose stop myapp
}

run_post_backup_operations() {
    # Restart service
    docker compose start myapp
}
```

### 6. Customize the logo

Replace `logo.png` with your own logo image (or update `LOGO_PATH` and `LOGO_FORMAT` in `.env`).

## Configuration Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `LOGS_DESTINATION` | Directory for backup logs | `./backup-logs/` |
| `UPLOAD_LOCATION` | Directory/files to backup | `/var/myapp` |
| `BORG_REPO` | BorgBackup repository URL | `ssh://user@host/~/backups` |
| `BORG_PASSPHRASE` | Repository encryption passphrase | `secure-password` |
| `BORG_RSH` | SSH command for remote repos | `ssh -i /path/to/key` |
| `KEEP_DAILY_BACKUPS` | Number of daily backups to keep | `7` |
| `KEEP_WEEKLY_BACKUPS` | Number of weekly backups to keep | `4` |
| `KEEP_MONTHLY_BACKUPS` | Number of monthly backups to keep | `6` |
| `FROM_EMAIL` | Sender email address | `alerts@example.com` |
| `FROM_NAME` | Sender display name | `Backup Alerts` |
| `TO_EMAIL` | Recipient email address | `admin@example.com` |
| `TO_NAME` | Recipient display name | `Admin` |
| `PROGRAM_NAME` | Application name for emails | `MyApp` |
| `LOGO_FORMAT` | Logo image format | `png` |
| `LOGO_PATH` | Path to logo file | `./logo.png` |
| `INSTANCE_URL` | Application URL (optional) | `https://app.example.com` |

## Usage

### Manual execution

```sh
./backup.sh
```

### Suppress success emails

```sh
./backup.sh --no-success-email
```

### Automated execution with cron

Add to your crontab (`crontab -e`):

```cron
# Run backup every day at 3 AM
0 3 * * * /path/to/backup.sh --no-success-email
```

Or use a systemd timer (recommended for better logging).

## Customization Guide

### Excluding files from backup

Edit the `borg create` command in `backup.sh` to add exclusions:

```sh
borg create \
    ... \
    ::"{hostname}-{now}" \
    "$UPLOAD_LOCATION" \
    --exclude "$UPLOAD_LOCATION/cache/" \
    --exclude "*.tmp" \
    --exclude "$UPLOAD_LOCATION/logs/"
```

### Adjusting retention policy

Modify these variables in `.env`:

```sh
KEEP_DAILY_BACKUPS=7    # Keep 7 daily backups
KEEP_WEEKLY_BACKUPS=4   # Keep 4 weekly backups
KEEP_MONTHLY_BACKUPS=6  # Keep 6 monthly backups
```

### Custom pre/post operations

The script provides two hook functions you can customize:

- `run_pre_backup_operations()` - Runs before backup (e.g., database dumps, stopping services)
- `run_post_backup_operations()` - Runs after backup (e.g., restarting services, cleanup)

## Email Notifications

The script sends HTML-formatted email notifications that include:

- Backup status (success/failure)
- System information (hostname, OS)
- Repository details
- Complete backup logs
- Timestamp

You'll receive emails for:
- Successful backups (can be disabled with `--no-success-email`)
- Failed backups
- Repository connectivity issues

## Troubleshooting

### Permission denied errors

Ensure the script has execute permissions:

```sh
chmod +x backup.sh
```

### msmtp authentication issues

Test your msmtp configuration:

```sh
echo "Test email" | msmtp your-email@example.com
```

### BorgBackup connectivity issues

Test repository access:

```sh
export BORG_REPO="your-repo-url"
export BORG_PASSPHRASE="your-passphrase"
borg info
```

### Missing dependencies

Run the script once - it will tell you which commands are missing.

## Security Considerations

- Store your `.env` file securely (it's in `.gitignore` by default)
- Use strong passphrases for BorgBackup encryption
- Secure your SSH keys with proper permissions (600)
- Consider using SSH key authentication instead of passwords
- Regularly test your backups by performing restores

## Restoring Backups

Restoring backups works as with any borg repository, check borg's documentation.