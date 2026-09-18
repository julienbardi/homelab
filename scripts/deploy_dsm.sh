#!/bin/sh
# deploy_dsm.sh
# Idempotent DSM certificate deployment via WebAPI

set -eu

HOST="${1:?Missing DSM hostname}"
USER="${2:?Missing DSM username}"
PASS="${DSM_PASS:-${DSM_PASSWORD:-${NAS_PASSWORD:-${PASSWORD:-${dsm_password:-${nas_password:-}}}}}}"
if [ -z "$PASS" ]; then
    echo "❌ [dsm] Missing password. Available environment variables:" >&2
    env | grep -iE 'dsm|nas|pass' >&2 || true
    exit 1
fi

CERT_DIR="${4:-/var/lib/ssl/canonical}"

FULLCHAIN="${CERT_DIR}/fullchain_rsa.pem"
PRIVKEY="${CERT_DIR}/privkey_rsa.pem"
CA_CER="${CERT_DIR}/ca.cer"

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

log() { echo "$1"; }

# 1. Login
log "🔐 [dsm] Authenticating with DSM…"

ENC_USER=$(USER_ARG="$USER" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ.get("USER_ARG", "")))')
ENC_PASS=$(PASS_ARG="$PASS" python3 -c 'import os, urllib.parse; print(urllib.parse.quote(os.environ.get("PASS_ARG", "")))')

RESP=$(curl -sk -c "$COOKIE_JAR" "https://${HOST}:5001/webapi/auth.cgi?api=SYNO.API.Auth&version=6&method=login&account=${ENC_USER}&passwd=${ENC_PASS}&session=core&format=cookie")
SID=$(printf '%s' "$RESP" | grep -o '"sid":"[^"]*"' | cut -d'"' -f4)

if [ -z "$SID" ]; then
    log "❌ [dsm] Authentication failed"
    exit 1
fi

log "🟢 [dsm] Authenticated (SID acquired)"

# 2. Copy certs into AppArmor-safe RAM directory
TMPDIR=$(mktemp -d /run/user/"$(id -u)"/dsm.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

log "📁 [dsm] Copying canonical certs into RAM-safe temp directory…"

# Root can always read with cat, even when cp fails. This is a known ZFS behavior.
/usr/local/bin/run-as-root.sh sh -c "cat \"$PRIVKEY\""   > "$TMPDIR/privkey_rsa.pem"
/usr/local/bin/run-as-root.sh sh -c "cat \"$FULLCHAIN\"" > "$TMPDIR/fullchain_rsa.pem"

log "🔧 [dsm] Converting RSA private key to PKCS#8…"

openssl pkcs8 -topk8 -nocrypt \
    -in "$TMPDIR/privkey_rsa.pem" \
    -out "$TMPDIR/privkey_pkcs8.pem"

# 3a. Trim fullchain to DSM‑compatible chain (leaf + intermediate only)
log "🔧 [dsm] Trimming fullchain to DSM‑compatible chain…"

TRIMMED_CHAIN="$TMPDIR/fullchain_trimmed.pem"

awk '
  /BEGIN CERTIFICATE/ { c++ }
  c <= 2 { print }
' "$TMPDIR/fullchain_rsa.pem" > "$TRIMMED_CHAIN"

# Replace the original fullchain with the trimmed version
mv "$TRIMMED_CHAIN" "$TMPDIR/fullchain_rsa.pem"

# 3. Combine inside RAM temp
log "📦 [dsm] Combining certificate + key for DSM…"

COMBINED="$TMPDIR/dsm_combined.pem"
cat "$TMPDIR/privkey_pkcs8.pem" "$TMPDIR/fullchain_rsa.pem" > "$COMBINED"

#echo "DEBUG: Combined PEM contents (secret):"
#cat "$COMBINED"

if [ ! -s "$COMBINED" ]; then
    log "❌ [dsm] Combined PEM is empty — aborting"
    exit 1
fi

# 4. Upload
log "📥 [dsm] Uploading combined certificate…"

curl -sk -b "$COOKIE_JAR" -X POST \
  -F "api=SYNO.Core.Certificate" \
  -F "version=1" \
  -F "method=import" \
  -F "_sid=$SID" \
  -F "file=@${COMBINED};filename=dsm_combined.pem" \
  -F "desc=Homelab-Auto-Deploy" \
  "https://${HOST}:5001/webapi/entry.cgi" > /tmp/dsm_upload.log 2>&1

echo "DEBUG: Combined PEM contents (secret):"
sed -n '1,200p' "$COMBINED"

if ! grep -q '"success":true' /tmp/dsm_upload.log; then
    log "❌ [dsm] Upload failed:"
    cat /tmp/dsm_upload.log
    exit 26
fi

log "📦 [dsm] Certificate uploaded"

# 5. Set Default
CERT_LIST=$(curl -sk -b "$COOKIE_JAR" \
  "https://${HOST}:5001/webapi/entry.cgi?api=SYNO.Core.Certificate&version=1&method=list&_sid=$SID")

NEW_ID=$(printf '%s' "$CERT_LIST" | grep -o '"id":"[^"]*"' | tail -n1 | cut -d'"' -f4)

if [ -n "$NEW_ID" ]; then
    log "🚀 [dsm] Activating certificate ID ${NEW_ID}…"
    curl -sk -b "$COOKIE_JAR" \
      "https://${HOST}:5001/webapi/entry.cgi?api=SYNO.Core.Certificate&version=1&method=set_default&id=${NEW_ID}&_sid=$SID" >/dev/null
fi

log "🔄 [dsm] Restarting DSM reverse proxy…"
curl -sk -b "$COOKIE_JAR" \
  "https://${HOST}:5001/webapi/entry.cgi?api=SYNO.Core.Service&version=1&method=restart&service=nginx&_sid=$SID" \
  >/dev/null

log "🟢 [dsm] DSM certificate deployment complete"
