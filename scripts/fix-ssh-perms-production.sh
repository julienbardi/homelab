#!/bin/sh
# fix-ssh-perms-production.sh
# POSIX /bin/sh script: dry-run by default; use --apply to change
# Usage: ./fix-ssh-perms-production.sh [--apply] [--min-uid N] [--log /path/to/log]
# Default MIN_UID = 1000

set -eu

# Defaults
DRY_RUN=1
MIN_UID=1000
# By default prefer syslog (use `logger`). Use --log to override to a file
LOGFILE=""
LOG_TO_SYSLOG=1

# Simple arg parsing
while [ "${1:-}" != "" ]; do
    case "$1" in
        --apply)
            DRY_RUN=0
            shift
            ;;
        --min-uid)
            shift
            MIN_UID=${1:-$MIN_UID}
            shift
            ;;
        --log)
            shift
            val=${1:-}
            shift
            if [ "${val}" = "syslog" ] || [ "${val}" = "" ]; then
                LOG_TO_SYSLOG=1
                LOGFILE=""
            else
                LOG_TO_SYSLOG=0
                LOGFILE=${val}
            fi
            ;;
        --help)
            cat <<EOF
Usage: $0 [--apply] [--min-uid N] [--log /path/to/log|syslog]
    --apply        actually apply changes (default is dry run)
    --min-uid N    minimum UID to consider as regular users (default 1000)
    --log PATH     log file (default uses syslog). Use "syslog" to force syslog.
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

# Ensure log destination available or fallback
if [ "$DRY_RUN" -eq 1 ]; then
    : # dry-run does not require log write permission
else
    if [ "$LOG_TO_SYSLOG" -eq 1 ]; then
        if command -v logger >/dev/null 2>&1; then
            : # syslog available
        else
            LOG_TO_SYSLOG=0
            LOGFILE="/tmp/fix-ssh-perms.log"
            touch "$LOGFILE" >/dev/null 2>&1 || { echo "Cannot write to $LOGFILE"; exit 1; }
        fi
    else
        if ! touch "$LOGFILE" >/dev/null 2>&1; then
            LOGFILE="/tmp/fix-ssh-perms.log"
            touch "$LOGFILE" || { echo "Cannot write to $LOGFILE"; exit 1; }
        fi
    fi
fi

log() {
    if [ "$LOG_TO_SYSLOG" -eq 1 ]; then
        # Use logger to send to syslog, also echo to stdout for visibility
        if command -v logger >/dev/null 2>&1; then
            logger -t fix-ssh-perms -- "$1" 2>/dev/null || true
            printf '%s\n' "$1"
            return
        fi
    fi

    ts=$(date +"%Y-%m-%d %H:%M:%S")
    printf '%s %s\n' "$ts" "$1" >>"$LOGFILE" 2>/dev/null || true
    printf '%s\n' "$1"
}

# Safety check: require root for operations that change other users
IS_ROOT=0
if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=1
fi

log "ℹ️ Starting fix-ssh-perms script (dry-run=${DRY_RUN}, min_uid=${MIN_UID})"

# Iterate users with UID >= MIN_UID
getent passwd | awk -F: -v min="$MIN_UID" '$3 >= min { print $1 ":" $6 }' | \
while IFS=: read -r USER HOME; do
    log "🔎 User: $USER"

    if [ ! -d "$HOME" ]; then
        log "� ️ Home not found: $HOME"
        continue
    fi

    SSH_DIR="$HOME/.ssh"
    if [ ! -d "$SSH_DIR" ]; then
        log "� ️ $SSH_DIR does not exist"
        continue
    fi

    log "ℹ️ Inspecting $SSH_DIR"
    stat -c '%A %U:%G %n' -- "$SSH_DIR" 2>/dev/null || true
    ls -l -- "$SSH_DIR" 2>/dev/null || true

    # If root, ensure group exists and set ownership
    if [ "$IS_ROOT" -eq 1 ]; then
        if getent group "$USER" >/dev/null 2>&1; then
            log "ℹ️ Group '$USER' exists"
        else
            if [ "$DRY_RUN" -eq 1 ]; then
                log "🧪 Would create group: groupadd -- \"$USER\""
            else
                if groupadd -- "$USER" >/dev/null 2>&1; then
                    log "✅ Created group '$USER'"
                else
                    log "� ️ Failed to create group '$USER'"
                fi
            fi
        fi

        if [ "$DRY_RUN" -eq 1 ]; then
            log "🧪 Would chown -R $USER:$USER $SSH_DIR"
        else
            if chown -R -- "$USER":"$USER" "$SSH_DIR" >/dev/null 2>&1; then
                log "✅ chown -R $USER:$USER $SSH_DIR"
            else
                log "� ️ chown failed for $SSH_DIR"
            fi
        fi
    else
        log "ℹ️ Not root: skipping group creation and chown"
    fi

    # Set safe perms for .ssh and home
    if [ "$DRY_RUN" -eq 1 ]; then
        log "🧪 Would chmod 700 $SSH_DIR"
        log "🧪 Would chmod 755 $HOME"
    else
        if chmod 700 -- "$SSH_DIR" >/dev/null 2>&1; then
            log "✅ chmod 700 $SSH_DIR"
        else
            log "� ️ chmod 700 failed for $SSH_DIR"
        fi

        if chmod 755 -- "$HOME" >/dev/null 2>&1; then
            log "✅ chmod 755 $HOME"
        else
            log "� ️ chmod 755 failed for $HOME"
        fi
    fi

    # Fix files inside .ssh
    find "$SSH_DIR" -maxdepth 1 -type f -print 2>/dev/null | while IFS= read -r f; do
        base=$(basename -- "$f")
        case "$base" in
            *.pub) mode=644 ;;
            authorized_keys) mode=600 ;;
            known_hosts) mode=644 ;;
            *) mode=600 ;;
        esac

        if [ "$DRY_RUN" -eq 1 ]; then
            log "🧪 Would chmod $mode $f"
        else
            if chmod "$mode" -- "$f" >/dev/null 2>&1; then
                log "✅ chmod $mode $f"
            else
                log "� ️ chmod $mode failed for $f"
            fi
        fi
    done

    # Ensure parent directories up to / are not group/world writable
    log "� ️ Checking parent directories from $HOME up to /"
    p="$HOME"
    while [ "$p" != "/" ]; do
        if [ -d "$p" ]; then
            if find "$p" -maxdepth 0 -perm /022 >/dev/null 2>&1; then
                if [ "$DRY_RUN" -eq 1 ]; then
                    log "🧪 Would chmod go-w $p"
                else
                    if chmod go-w -- "$p" >/dev/null 2>&1; then
                        log "✅ chmod go-w $p"
                    else
                        log "� ️ chmod go-w failed for $p"
                    fi
                fi
            else
                log "✅ $p OK"
            fi
        else
            log "ℹ️ $p does not exist"
        fi
        p=$(dirname -- "$p")
    done

    # Check root
    if find / -maxdepth 0 -perm /022 >/dev/null 2>&1; then
        log "� ️ / is group/world writable (manual review required)"
    else
        log "✅ / OK"
    fi
done

log "ℹ️ Completed run (dry-run=${DRY_RUN}). Log: ${LOGFILE:-syslog}"
