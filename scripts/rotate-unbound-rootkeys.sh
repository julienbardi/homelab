#!/bin/sh
# rotate-unbound-rootkeys.sh
# Atomic, idempotent DNSSEC trust anchor refresh for Unbound.

set -eu

ROOT_KEY="/var/lib/unbound/root.key"
ROOT_DIR="$(dirname "$ROOT_KEY")"
OWNER_USER="root"
OWNER_GROUP="unbound"
MODE="0644"
SERVICE="unbound"

log() {
    printf '%s [rotate-unbound-rootkeys] %s\n' \
        "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

cleanup() {
    [ -n "${TMP:-}" ] && [ -f "$TMP" ] && rm -f "$TMP" || true
}
trap cleanup EXIT INT TERM

log "Refreshing DNSSEC trust anchors..."

# Ensure directory exists
install -d -m 0755 -o "$OWNER_USER" -g "$OWNER_GROUP" "$ROOT_DIR"

# Create temp file on same filesystem with strict umask
TMP="$(mktemp -p "$ROOT_DIR" root.key.XXXXXX)"

# Fetch trust anchors into temp file
if ! unbound-anchor -a "$TMP"; then
    # Some unbound-anchor builds return non-zero even when they wrote a valid anchor.
    if [ -s "$TMP" ] && grep -q 'IN[[:space:]]\+DNSKEY' "$TMP"; then
        log "WARN: unbound-anchor returned non-zero but produced a valid trust anchor; continuing"
    else
        log "ERROR: unbound-anchor failed and no valid trust anchor was produced; leaving existing root.key untouched"
        exit 1
    fi
fi

# Validate: must contain at least one DNSKEY
if [ ! -s "$TMP" ] || ! grep -q 'IN[[:space:]]\+DNSKEY' "$TMP"; then
    log "ERROR: invalid trust anchor file (missing DNSKEY); aborting"
    exit 1
fi

COUNT_DNSKEYS="$(grep -c 'IN[[:space:]]\+DNSKEY' "$TMP" || true)"
log "Validated $COUNT_DNSKEYS DNSKEY record(s)"

# Canonicalize ownership and permissions
if ! chown "$OWNER_USER:$OWNER_GROUP" "$TMP"; then
    log "ERROR: chown failed — cannot set group to '$OWNER_GROUP'"
    exit 1
fi
chmod "$MODE" "$TMP"

# Paranoid: ensure data is flushed before atomic replace (optional but harmless)
sync "$TMP" || true

# Atomic replace
mv "$TMP" "$ROOT_KEY"
TMP=""

log "OK: Trust anchors refreshed at $ROOT_KEY"

# Restart Unbound if present
if command -v systemctl >/dev/null 2>&1; then
    if systemctl status "$SERVICE" >/dev/null 2>&1; then
        log "Restarting Unbound service..."
        sync
        sleep 1
        if systemctl restart "$SERVICE"; then
            log "OK: Unbound restarted successfully"
        else
            log "WARN: Unbound restart failed; trust anchors updated but service not restarted"
            exit 1
        fi
    fi
fi

log "Trust anchor rotation complete."
