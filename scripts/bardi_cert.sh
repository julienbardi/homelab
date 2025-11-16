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
  
  # copy new certs atomically
  cp "$SSL_CHAIN_ECC" "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem"
  cp "$SSL_KEY_ECC" "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem"

  chmod 600 "$SSL_DEPLOY_DIR_HEADSCALE"/*

  # tighten on-disk permissions (owner headscale; group headscale kept as-is)
  sudo chown headscale:headscale /etc/headscale/ssl/privkey.pem /etc/headscale/ssl/fullchain.pem
  chmod 0640 /etc/headscale/certs/privkey.pem
  chmod 0644 /etc/headscale/certs/fullchain.pem

  # ensure ACL grants only the caddy service read access (idempotent)
  setfacl -m u:caddy:r /etc/headscale/certs/privkey.pem
  setfacl -m u:caddy:r /etc/headscale/certs/fullchain.pem

  systemctl restart headscale || true

  # validate Caddy can read the key before reloading; if not, fail loudly
  if sudo -u caddy test -r "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem"; then
    log "[cert] caddy can read private key, reloading caddy"
    /usr/bin/caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
  else
    echo "$(date -Iseconds) [cert][ERROR] caddy cannot read $SSL_DEPLOY_DIR_HEADSCALE/privkey.pem" >&2
    exit 1
  fi
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
