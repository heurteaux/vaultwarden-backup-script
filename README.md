# Vaultwarden Backup Script

A POSIX-compliant automated backup script for Vaultwarden using BorgBackup with email notifications. This script follows the official [Vaultwarden backup guide](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault).

## Features

- Secure encrypted backups using BorgBackup
- Backs up all critical Vaultwarden data:
  - SQLite database
  - Attachments directory
  - Sends directory
  - config.json
  - RSA key files
- Email notifications with detailed logs
- Automatic pruning with configurable retention policies
- HTML email reports
- POSIX compliant

## What Gets Backed Up

According to the [official Vaultwarden backup guide](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault), this script backs up:

### Required
- **SQLite database** (`db.sqlite3`) - Contains all vault data, user/org/device metadata
- **Attachments directory** - File attachments stored outside the database

### Recommended
- **config.json** - Admin panel configuration
- **RSA key files** (`rsa_key*`) - Used to sign JWT authentication tokens

### Optional
- **Sends directory** - Send file attachments (ephemeral by design)

### Not backed up
- **icon_cache directory** - Website icons (can be refetched)

## Prerequisites

The following tools must be installed on your system:

- `borg` (BorgBackup)
- `msmtp` (for email sending)
- `envsubst` (usually part of `gettext`)
- `sqlite3` (if not using Docker or built-in vaultwarden backup)
- Standard Unix utilities: `base64`, `grep`, `hostname`, `date`, `fold`, `cat`

### Installation on Debian/Ubuntu

```sh
sudo apt install borgbackup msmtp gettext-base sqlite3
```

## Setup

### 1. Clone the repository

```sh
git clone https://github.com/heurteaux/vaultwarden-backup-script.git
cd vaultwarden-backup-script
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

### 5. Configure Vaultwarden-specific settings

The script is already configured for Vaultwarden. Make sure your `.env` file has the correct paths:

**For Docker installations:**
```sh
USE_DOCKER=true
CONTAINER_RUNTIME="docker"
VAULTWARDEN_CONTAINER="vaultwarden"
UPLOAD_LOCATION="/path/to/vaultwarden/data"  # On the host
```

**For Podman installations:**
```sh
USE_DOCKER=true
CONTAINER_RUNTIME="podman"
VAULTWARDEN_CONTAINER="vaultwarden"
UPLOAD_LOCATION="/path/to/vaultwarden/data"  # On the host
```

### 6. Customize the logo

Replace `logo.png` with your own logo image, or use the Vaultwarden logo (or update `LOGO_PATH` and `LOGO_FORMAT` in `.env`).

## Configuration Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `LOGS_DESTINATION` | Directory for backup logs | `./backup-logs/` |
| `UPLOAD_LOCATION` | Vaultwarden data directory (backed up directly) | `/var/lib/vaultwarden/data` |
| `USE_DOCKER` | Whether Vaultwarden runs in a container | `true` or `false` |
| `CONTAINER_RUNTIME` | Container runtime command (if using containers) | `docker`, `podman`, `nerdctl` |
| `VAULTWARDEN_CONTAINER` | Container name (if using containers) | `vaultwarden` |
| `VAULTWARDEN_BINARY_PATH` | Path to vaultwarden binary (optional) | `/usr/bin/vaultwarden` |
| `BORG_REPO` | BorgBackup repository URL | `ssh://user@host/~/backups` |
| `BORG_PASSPHRASE` | Repository encryption passphrase | `secure-password` |
| `BORG_RSH` | SSH command for remote repos | `ssh -i /path/to/key` |
| `KEEP_DAILY_BACKUPS` | Number of daily backups to keep | `7` |
| `KEEP_WEEKLY_BACKUPS` | Number of weekly backups to keep | `4` |
| `KEEP_MONTHLY_BACKUPS` | Number of monthly backups to keep | `6` |
| `FROM_EMAIL` | Sender email address | `vaultwarden-backup@example.com` |
| `FROM_NAME` | Sender display name | `Vaultwarden Backup` |
| `TO_EMAIL` | Recipient email address | `admin@example.com` |
| `TO_NAME` | Recipient display name | `Admin` |
| `PROGRAM_NAME` | Application name for emails | `Vaultwarden` |
| `LOGO_FORMAT` | Logo image format | `png` |
| `LOGO_PATH` | Path to logo file | `./logo.png` |
| `INSTANCE_URL` | Vaultwarden URL (optional) | `https://vault.example.com` |

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

### Excluding directories from backup

By default, the script backs up the entire vaultwarden data directory. To exclude `icon_cache` (recommended to save space), edit the `borg create` command in [backup.sh](backup.sh):

```sh
borg create \
    ... \
    ::"{hostname}-{now}" \
    "$UPLOAD_LOCATION" \
    --exclude "$UPLOAD_LOCATION/icon_cache/"
```

### Adjusting retention policy

Modify these variables in `.env`:

```sh
KEEP_DAILY_BACKUPS=7    # Keep 7 daily backups
KEEP_WEEKLY_BACKUPS=4   # Keep 4 weekly backups
KEEP_MONTHLY_BACKUPS=6  # Keep 6 monthly backups
```

## Backup Process

The script performs the following steps:

1. **Pre-backup operations:**
   - Creates a timestamped database backup file within the vaultwarden data directory using sqlite3 `.backup` command
   - This ensures database consistency even if vaultwarden is actively running

2. **BorgBackup operations:**
   - Backs up the entire vaultwarden data directory (including the timestamped db backup, attachments, sends, config.json, RSA keys, etc.)
   - Creates encrypted backup archive
   - Prunes old backups according to retention policy
   - Compacts repository

## Restoring Backups

To restore a Vaultwarden backup:

1. **Stop Vaultwarden:**
   ```sh
   # Docker
   docker stop vaultwarden
   
   # Native
   systemctl stop vaultwarden
   ```

2. **Extract the backup:**
   ```sh
   # List available backups
   borg list
   
   # Mount a backup to browse
   mkdir /mnt/backup
   borg mount ::hostname-2025-01-03-030000 /mnt/backup
   
   # Or extract directly
   borg extract ::hostname-2025-01-03-030000
   ```

3. **Restore files:**
   ```sh
   # Remove old db.sqlite3-wal file (important!)
   rm /var/lib/vaultwarden/data/db.sqlite3-wal
   
   # Restore the entire data directory
   cp -r /mnt/backup/var/lib/vaultwarden/data/* /var/lib/vaultwarden/data/
   
   # Or restore specific files as needed
   cp /mnt/backup/var/lib/vaultwarden/data/db-backup-*.sqlite3 /var/lib/vaultwarden/data/db.sqlite3
   ```

4. **Set correct permissions:**
   ```sh
   chown -R vaultwarden:vaultwarden /var/lib/vaultwarden/data
   ```

5. **Start Vaultwarden:**
   ```sh
   # Docker
   docker start vaultwarden
   
   # Native
   systemctl start vaultwarden
   ```

**Important:** Always delete the `db.sqlite3-wal` file before restoring to avoid database corruption. See the [official guide](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault#restoring-backup-data) for details.

### Custom pre/post operations

The script provides two hook functions in [backup.sh](backup.sh) that are already configured for Vaultwarden:

- `run_pre_backup_operations()` - Prepares Vaultwarden data for backup
- `run_post_backup_operations()` - Cleans up temporary files after backup

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
- **Important for Vaultwarden:** 
  - The `config.json` contains sensitive data (admin token, SMTP credentials)
  - The `rsa_key.pem` can be used to forge authentication tokens
  - BorgBackup encryption helps protect these files, but consider additional security measures
  - Keep your backup server secure and isolated

## Additional Resources

- [Official Vaultwarden Backup Guide](https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault)
- [BorgBackup Documentation](https://borgbackup.readthedocs.io/)
- [Vaultwarden GitHub](https://github.com/dani-garcia/vaultwarden)

## Restoring Backups

Restoring backups works as with any borg repository, check borg's documentation.