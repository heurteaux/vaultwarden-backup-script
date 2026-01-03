#!/bin/sh
# This script is POSIX compliant

set -u

# ~~~ Command-line arguments ~~~

SEND_SUCCESS_EMAIL=true

for arg in "$@"; do
    case $arg in
        --no-success-email)
            SEND_SUCCESS_EMAIL=false
            shift
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--no-success-email]"
            exit 1
            ;;
    esac
done

# ~~~ Load configuration ~~~

SCRIPT_DIR="$(dirname "$0")"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Configuration file not found: $ENV_FILE"
    exit 1
fi

. "$ENV_FILE"

# Export variables that need to be available to subprocesses
export BORG_REPO
export BORG_PASSPHRASE
export BORG_RSH
export FROM_EMAIL
export FROM_NAME
export TO_EMAIL
export TO_NAME
export PROGRAM_NAME
export LOGO_FORMAT
export INSTANCE_URL

# ~~~ Logging helper functions ~~~

_log_format() { printf "%s [%s]: %s\n" "$(date +'%d/%m/%Y %H:%M:%S')" "$1" "$2"; }

info() { _log_format "INFO" "$@"; }
warn() { _log_format "WARN" "$@">&2; }
error() { _log_format "ERROR" "$@">&2; }
success() { _log_format "SUCCESS" "$@"; }

# ~~~ Logging setup ~~~

mkdir -p "$LOGS_DESTINATION"
OUTPUT_FILE="$LOGS_DESTINATION/backup_$(date +'%Y-%m-%d_%H-%M-%S').log"
exec >"$OUTPUT_FILE" 2>&1 # redirects stdout and stderr to previously declared log file 

# ~~~ Checks installed tools ~~~

info "checking script dependencies..."

required="base64 grep hostname date envsubst fold msmtp cat borg"

missing=
for cmd in $required; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing="${missing}${cmd} "
    fi
done

if [ -n "$missing" ]; then
    error "$(printf "missing required command(s): %s\n" "$missing")"
    exit 1
fi

# ~~~ Setting up email constants based on configuration ~~~

if [ ! -f "$LOGO_PATH" ]; then
    error "Logo file not found: $LOGO_PATH"
    exit 1
fi

if  [ ! -f "$EMAIL_TEMPLATE" ] || [ ! -r "$EMAIL_TEMPLATE" ] ; then
    error "Cannot read email template: $EMAIL_TEMPLATE"
    exit 1
fi

LOGO_IMG="$(base64 "$LOGO_PATH" | tr -d '\n')"
FORMATTED_HOSTNAME="$(hostname)"
OS_NAME="$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
BACKUP_TIME="$(date +'%d/%m/%Y %H:%M:%S')"
PARAGRAPH="encountered problems during backup, please review logs carefully" # default value, overwritten on backup success

export EMAIL_TEMPLATE
export LOGO_PATH
export LOGO_IMG
export FORMATTED_HOSTNAME
export OS_NAME
export BACKUP_TIME
export PARAGRAPH

# ~~~ Service specific operations ~~~
# Customize these functions based on your backup needs

run_pre_backup_operations() {
    # Add your pre-backup operations here
    # Examples:
    # - Stop services for consistent backups
    # - Create database dumps
    # - Prepare data for backup
    
    # Example database dump:
    # docker exec -t myapp_db pg_dumpall --clean --if-exists --username="$DB_USERNAME" > "$UPLOAD_LOCATION"/database-backup/database.sql
    
    : # No-op (remove this line when adding your operations)
}

run_post_backup_operations() {
    # Add your post-backup operations here
    # Examples:
    # - Restart services
    # - Clean up temporary files
    # - Send additional notifications
    
    : # No-op (remove this line when adding your operations)
}

# ~~~ Cleanup trap in case of uncaught error ~~~

CLEANUP_DONE=false
ERROR_HANDLED=false

cleanup() {
    _exit_status=$?
    if [ "$CLEANUP_DONE" = "false" ]; then
        CLEANUP_DONE=true
        # Send error email for uncaught errors
        if [ "$_exit_status" -ne 0 ] && [ "$ERROR_HANDLED" = "false" ]; then
            error "Uncaught error occurred (exit status $_exit_status)"
            send_error_email || true  # Don't fail if email sending fails
        fi
        run_post_backup_operations
    fi
}

trap cleanup EXIT

# ~~~ Error Handling ~~~

handle_errors() {
    _step_name="$1"
    _exit_code="$2"

    if [ "$_exit_code" -eq 0 ]
    then 
        info "$_step_name finished successfully"
    else
        error "$_step_name finished with errors (exit code $_exit_code)"
        ERROR_HANDLED=true
        send_error_email
        cleanup
        exit "$_exit_code"
    fi
}

# ~~~ Email alert functions ~~~

send_pretty_email() {
    if [ ! -f "$OUTPUT_FILE" ] || [ ! -r "$OUTPUT_FILE" ]; then
        error "Cannot read log file: $OUTPUT_FILE"
        exit 1
    fi
    
    if ! LOGS="$(cat "$OUTPUT_FILE" 2>&1)"; then
        error "Failed to read log file: $OUTPUT_FILE"
        exit 1
    fi
    export LOGS

    if ! cat "$EMAIL_TEMPLATE" | envsubst | fold -s -w 998 | msmtp "$TO_EMAIL"
    then
        error "failed to send alert email"
        exit 1
    fi
}

send_error_email() {
    export SUBJECT="Backup failed"
    export TITLE="failed"
    send_pretty_email
}

send_success_email() {
    export SUBJECT="Backup completed successfully"
    export TITLE="completed successfully"
    export PARAGRAPH="successfully backed up all data"
    send_pretty_email
}

send_connectivity_error_email() {
    export SUBJECT="Backup failed - Cannot reach repository"
    export TITLE="failed - cannot reach repository"
    send_pretty_email
}

# ~~~ Main backup process ~~~

info "Running pre-backup operations..."

run_pre_backup_operations

PRE_BACKUP_OPERATIONS_EXIT_CODE=$?
handle_errors "Pre-backup operations" "$PRE_BACKUP_OPERATIONS_EXIT_CODE"

info "Checking repository connectivity..."

if ! borg info
then
    CONNECTIVITY_EXIT_CODE=$?
    error "Cannot reach borg repository (exit code $CONNECTIVITY_EXIT_CODE)"
    send_connectivity_error_email
    exit $CONNECTIVITY_EXIT_CODE
fi

info "Repository connectivity check passed"
info "Starting backup..."

# Backup the most important directories into an archive named after
# the machine this script is currently running on:

borg create                         \
    --filter AME                    \
    --list                          \
    --stats                         \
    --show-rc                       \
    --compression lz4               \
    --exclude-caches                \
                                    \
    ::"{hostname}-{now}"            \
    "$UPLOAD_LOCATION"
    # Add custom exclusions here if needed:
    # --exclude "$UPLOAD_LOCATION/cache/" \
    # --exclude "$UPLOAD_LOCATION/temp/" \
    # --exclude "*.tmp"

BACKUP_EXIT_CODE=$?
handle_errors "Backup" $BACKUP_EXIT_CODE

info "Pruning repository..."

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-*' matching is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

borg prune                          \
    --list                          \
    --glob-archives '{hostname}-*'  \
    --show-rc                       \
    --keep-daily    "$KEEP_DAILY_BACKUPS"               \
    --keep-weekly   "$KEEP_WEEKLY_BACKUPS"               \
    --keep-monthly  "$KEEP_MONTHLY_BACKUPS"

PRUNE_EXIT_CODE=$?
handle_errors "Pruning" $PRUNE_EXIT_CODE

# Compacting backup segments

info "Compacting repository..."

borg compact

COMPACT_EXIT_CODE=$?
handle_errors "Compacting" $COMPACT_EXIT_CODE

info "Running post-backup operations..."

run_post_backup_operations

POST_BACKUP_OPERATIONS_EXIT_CODE=$?
handle_errors "Post-backup operations" "$POST_BACKUP_OPERATIONS_EXIT_CODE"

success "Successfully backed up data"

if [ "$SEND_SUCCESS_EMAIL" = "true" ];
then
    info "Sending success notification email..."
    send_success_email
    info "Success notification sent"
else
    info "Success notification silenced (--no-success-email flag enabled)"
fi