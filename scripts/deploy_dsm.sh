#!/bin/sh
# ------------------------------------------------------------------
# deploy_dsm.sh v2
#
# CONTRACT:
# - Does NOT create new DSM certificate objects.
# - Does NOT use SYNO.Core.Certificate.import.
# - Updates the currently active DSM certificate in-place.
# - Discovers active certificate ID from DSM DEFAULT pointer.
# - Creates rollback backup before modification.
# - Verifies certificate/key consistency before deployment.
# - Restarts DSM nginx and waits for completion.
# ------------------------------------------------------------------

set -eu

CERT_DIR="${1:-/var/lib/ssl/canonical}"

FULLCHAIN="${CERT_DIR}/fullchain_rsa.pem"
PRIVKEY="${CERT_DIR}/privkey_rsa.pem"

ARCHIVE_BASE="/usr/syno/etc/certificate/_archive"

log() {
    printf '%s\n' "$*"
}

fail() {
    printf '❌ %s\n' "$*" >&2
    exit 1
}

# ------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------

[ -r "$FULLCHAIN" ] || fail "missing $FULLCHAIN"
[ -r "$PRIVKEY" ]   || fail "missing $PRIVKEY"

CERT_MODULUS=$(
    openssl x509 -in "$FULLCHAIN" -noout -modulus |
    sha256sum | awk '{print $1}'
)

KEY_MODULUS=$(
    openssl rsa -in "$PRIVKEY" -noout -modulus 2>/dev/null |
    sha256sum | awk '{print $1}'
)

[ "$CERT_MODULUS" = "$KEY_MODULUS" ] || \
    fail "certificate/private-key mismatch"

# ------------------------------------------------------------------
# Discover active certificate
# ------------------------------------------------------------------

ACTIVE_ID=$(sudo cat "${ARCHIVE_BASE}/DEFAULT")

[ -n "$ACTIVE_ID" ] || fail "unable to determine active certificate"

ACTIVE_DIR="${ARCHIVE_BASE}/${ACTIVE_ID}"

log "ℹ️ Active DSM certificate: ${ACTIVE_ID}"

[ -d "$ACTIVE_DIR" ] || fail "missing ${ACTIVE_DIR}"

# ------------------------------------------------------------------
# Backup
# ------------------------------------------------------------------

BACKUP_DIR="/root/cert-backup/$(date +%Y%m%d-%H%M%S)"

log "📦 Creating backup in ${BACKUP_DIR}"

sudo mkdir -p "$BACKUP_DIR"

sudo cp "${ACTIVE_DIR}/cert.pem"      "$BACKUP_DIR/"
sudo cp "${ACTIVE_DIR}/fullchain.pem" "$BACKUP_DIR/"
sudo cp "${ACTIVE_DIR}/privkey.pem"   "$BACKUP_DIR/"

# ------------------------------------------------------------------
# Replace active certificate
# ------------------------------------------------------------------

log "📥 Installing certificate into ${ACTIVE_ID}"

sudo cp "$FULLCHAIN" "${ACTIVE_DIR}/fullchain.pem"
sudo cp "$FULLCHAIN" "${ACTIVE_DIR}/cert.pem"
sudo cp "$PRIVKEY"   "${ACTIVE_DIR}/privkey.pem"

sudo chmod 400 \
    "${ACTIVE_DIR}/cert.pem" \
    "${ACTIVE_DIR}/fullchain.pem" \
    "${ACTIVE_DIR}/privkey.pem"

# ------------------------------------------------------------------
# Refresh DSM mirrors
# ------------------------------------------------------------------

for d in \
    /usr/syno/etc/certificate/system/default \
    /usr/syno/etc/certificate/system/FQDN
do
    if [ -d "$d" ]; then
        sudo cp "$FULLCHAIN" "$d/fullchain.pem"
        sudo cp "$FULLCHAIN" "$d/cert.pem"
        sudo cp "$PRIVKEY"   "$d/privkey.pem"

        sudo chmod 400 \
            "$d/cert.pem" \
            "$d/fullchain.pem" \
            "$d/privkey.pem"
    fi
done

# ------------------------------------------------------------------
# Reload DSM web stack
# ------------------------------------------------------------------

log "🔄 Restarting DSM nginx (may take several minutes)"

sudo /usr/syno/bin/synosystemctl restart nginx

log "✅ DSM certificate deployment completed"