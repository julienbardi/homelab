#!/bin/bash
#
# bardi_cert.sh — Unified certificate workflow for bardi.ch
#
# Purpose:
#   - Issue/renew wildcard certs for bardi.ch + *.bardi.ch (RSA + ECC)
#   - Prepare/rebuild chain files if missing
#   - Deploy certs to devices (NAS, router, DiskStation, QNAP, Headscale)
#   - Restart services on devices after deployment
#   - Validate served certs (ECC and RSA handshakes)
#   - Safe for cron; logs actions and results
#
# Usage:
#   ./bardi_cert.sh issue
#   ./bardi_cert.sh prepare
#   ./bardi_cert.sh deploy [target]
#   ./bardi_cert.sh restart [target]
#   ./bardi_cert.sh validate
#   ./bardi_cert.sh all [target]
#   ./bardi_cert.sh help
#

set -euo pipefail

SCRIPT_VERSION="v1.3"

LOG=/home/julie/.acme.sh/bardi_cert.log
log() { echo "$*" | tee -a "$LOG"; }

# === [0] CONFIG ===
source /home/julie/.acme.sh/acme_env.sh
ACME=/home/julie/.acme.sh/acme.sh

RSA_DIR="/home/julie/.acme.sh/bardi.ch"
ECC_DIR="/home/julie/.acme.sh/bardi.ch_ecc"
DOMAINS=(-d bardi.ch -d '*.bardi.ch')

ROUTER="julie@192.168.50.1"
NAS="julie@192.168.50.4"
DISK="julie@192.168.50.2"
QNAP="admin@192.168.50.3"

LOCAL_DEPLOY="/etc/ssl/bardi.ch"

ACTION="${1:-help}"
TARGET="${2:-all}"
# === [1] ISSUE ===
# === [1] ISSUE ===
issue() {
  log "🔐 [1] Checking existing certificate validity"

  CERT_PATH="/etc/headscale/certs/fullchain.pem"
  if [ -f "$CERT_PATH" ]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

    if [ "$DAYS_LEFT" -gt 7 ]; then
      log "✅ Existing certificate valid for $DAYS_LEFT more days — skipping issuance"
      return
    else
      log "⚠️ Certificate expires in $DAYS_LEFT days — proceeding with issuance"
    fi
  else
    log "⛔ No existing certificate found — proceeding with issuance"
  fi

  # Explicitly use Let's Encrypt as CA
  $ACME --server letsencrypt --issue "${DOMAINS[@]}" --dns dns_infomaniak --keylength 4096 --force \
    || log "⚠️ RSA issuance failed"
  $ACME --server letsencrypt --issue "${DOMAINS[@]}" --dns dns_infomaniak --keylength ec-256 --ecc --force \
    || log "⚠️ ECC issuance failed"
}


# === [2] PREPARE ===
prepare() {
  log "🔧 [2] Preparing chain files"

  for TYPE in rsa ecc; do
    DIR="/home/julie/.acme.sh/bardi.ch${TYPE:+_ecc}"
    CERT="$DIR/bardi.ch.cer"
    CA="$DIR/ca.cer"
    CHAIN="$DIR/fullchain.cer"
    [[ -s "$CHAIN" ]] || {
      [[ -s "$CERT" && -s "$CA" ]] && cat "$CERT" "$CA" > "$CHAIN" && chmod 600 "$CHAIN" && log "🔧 Rebuilt $TYPE chain"
    }
  done
}
# === [3] DEPLOY ===
deploy() {
  local TARGET="${1:-all}"
  log "📦 [3] Deploying to $TARGET"

  ECC_CERT="$ECC_DIR/bardi.ch.cer"
  ECC_KEY="$ECC_DIR/bardi.ch.key"
  ECC_CHAIN="$ECC_DIR/fullchain.cer"

  ECC_CERT="/etc/letsencrypt/live/bardi.ch/fullchain.pem"
  ECC_KEY="/etc/letsencrypt/live/bardi.ch/privkey.pem"
  ECC_CHAIN="/etc/letsencrypt/live/bardi.ch/fullchain.pem"


  if [[ "$TARGET" == "all" || "$TARGET" == "headscale" ]]; then
    log "📦 Headscale → /etc/headscale/certs"
    sudo mkdir -p /etc/headscale/certs
    sudo rm -f /etc/headscale/certs/fullchain.pem
    sudo rm -f /etc/headscale/certs/privkey.pem

    sudo chmod 644 "$ECC_CHAIN"
    sudo chmod 600 "$ECC_KEY"
    sudo cp -a "$ECC_CHAIN" /etc/headscale/certs/fullchain.pem
    sudo cp -a "$ECC_KEY"   /etc/headscale/certs/privkey.pem
    sudo chmod 644 /etc/headscale/certs/fullchain.pem
    sudo chmod 600 /etc/headscale/certs/privkey.pem
    log "✅ Headscale certs deployed"

    # Auto-restart Headscale after cert update
    sudo systemctl restart headscale && log "🔄 Headscale service restarted"
  fi

  log "📦 [3] Deploying to $TARGET done"
}
# === [4] RESTART ===
restart() {
  local TARGET="${1:-all}"
  log "🔄 [4] Restarting services for $TARGET"
  [[ "$TARGET" == "all" || "$TARGET" == "headscale" ]] && \
    (sudo systemctl restart headscale && log "🔄 Headscale restarted")
}

# === [5] VALIDATE ===
validate() {
  log "🔍 [5] Validating Headscale cert"
  if openssl s_client -connect nas.bardi.ch:8912 -servername nas.bardi.ch -alpn h2 </dev/null 2>/dev/null | grep -q "DNS:*.bardi.ch"; then
    log "✅ Headscale cert includes wildcard SAN"
  else
    log "❌ Headscale cert missing wildcard SAN — handshake will fail"
    exit 1
  fi
}

# === [6] DISPATCH ===
case "$ACTION" in
  issue)      issue ;;
  prepare)    prepare ;;
  deploy)     deploy "$TARGET" ;;
  restart)    restart "$TARGET" ;;
  validate)   validate ;;
  all)
    log "🚀 Full workflow started: all → $TARGET"
    issue
    prepare
    deploy "$TARGET"
    restart "$TARGET"
    validate
    ;;
  help|*)     echo "Usage: $0 [issue|prepare|deploy|restart|validate|all] [target]" ;;
esac

# === [7] FOOTER ===
TIMESTAMP="$(date +'%F %T')"
log "🏁 bardi_cert.sh complete — $SCRIPT_VERSION @ $TIMESTAMP"
logger -t bardi_cert "bardi_cert workflow $SCRIPT_VERSION completed at $TIMESTAMP"
