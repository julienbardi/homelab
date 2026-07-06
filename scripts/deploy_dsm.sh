#!/bin/sh
# scripts/deploy_dsm.sh
# Idempotent DSM certificate deployment via WebAPI

set -eu

HOST="${1:?Missing DSM hostname}"
USER="${2:?Missing DSM username}"
PASS=$(cat <&8)
CERT_DIR="${4:-/var/lib/ssl/canonical}"

FULLCHAIN="${CERT_DIR}/fullchain.pem"
PRIVKEY="${CERT_DIR}/privkey.pem"
CA_CER="${CERT_DIR}/ca.cer"

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

log() { echo "$1"; }

# 1. Login
log "🔐 [dsm] Authenticating with DSM…"

ENC_USER=$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote('$USER'))")
ENC_PASS=$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote('$PASS'))")

RESP=$(curl -sk -c "$COOKIE_JAR" \
  "https://${HOST}:5001/webapi/auth.cgi?api=SYNO.API.Auth&version=6&method=login&account=${ENC_USER}&passwd=${ENC_PASS}&session=core&format=cookie")

SID=$(printf '%s' "$RESP" | grep -o '"sid":"[^"]*"' | cut -d'"' -f4)

if [ -z "$SID" ]; then
    log "❌ [dsm] Authentication failed"
    exit 1
fi

log "🟢 [dsm] Authenticated (SID acquired)"

# 2. Upload
log "📥 [dsm] Uploading certificate material…"
curl -sk -b "$COOKIE_JAR" -X POST \
  -F "api=SYNO.Core.Certificate" -F "version=1" -F "method=import" -F "_sid=$SID" \
  -F "key=@${PRIVKEY};filename=privkey.pem" \
  -F "cert=@${FULLCHAIN};filename=fullchain.pem" \
  -F "inter=@${CA_CER};filename=ca.cer" \
  -F "desc=Homelab-Auto-Deploy" \
  "https://${HOST}:5001/webapi/entry.cgi" > /tmp/dsm_upload.log 2>&1

if ! grep -q '"success":true' /tmp/dsm_upload.log; then
    log "❌ [dsm] Upload failed:"
    cat /tmp/dsm_upload.log
    exit 26
fi

log "📦 [dsm] Certificate uploaded"

# 3. Set Default
CERT_LIST=$(curl -sk -b "$COOKIE_JAR" \
  "https://${HOST}:5001/webapi/entry.cgi?api=SYNO.Core.Certificate&version=1&method=list&_sid=$SID")

NEW_ID=$(printf '%s' "$CERT_LIST" | grep -o '"id":"[^"]*"' | tail -n1 | cut -d'"' -f4)

if [ -n "$NEW_ID" ]; then
    log "🚀 [dsm] Activating certificate ID ${NEW_ID}…"
    curl -sk -b "$COOKIE_JAR" \
      "https://${HOST}:5001/webapi/entry.cgi?api=SYNO.Core.Certificate&version=1&method=set_default&id=${NEW_ID}&_sid=$SID" >/dev/null
fi

log "🟢 [dsm] DSM certificate deployment complete"