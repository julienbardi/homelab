#!/bin/bash
set -euo pipefail
source "/home/julie/homelab/scripts/config/homelab.env"

usage() {
  echo "Usage: $0 {issue|deploy headscale|validate|all headscale}"
  exit 1
}

issue() {
  log "[cert] issuing certificate for $DOMAIN"
  ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256
}

deploy_headscale() {
  log "[cert] deploying certificate for Headscale"
  mkdir -p "$SSL_DEPLOY_DIR_HEADSCALE"
  cp "$SSL_CHAIN_ECC" "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem"
  cp "$SSL_KEY_ECC" "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem"
  chmod 600 "$SSL_DEPLOY_DIR_HEADSCALE"/*
  systemctl restart headscale || true
}

validate() {
  log "[cert] validating deployed certificate"
  openssl x509 -in "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem" -noout -text | grep "CN="
}

all() {
  issue
  deploy_headscale
  validate
}

log() {
  echo "$(date -Iseconds) $1"
}

case "${1:-}" in
  issue) issue ;;
  deploy) [[ $# -eq 2 && "$2" == "headscale" ]] || usage; deploy_headscale ;;
  validate) validate ;;
  all) [[ $# -eq 2 && "$2" == "headscale" ]] || usage; all ;;
  *) usage ;;
esac
