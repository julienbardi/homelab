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

  # temp files to make updates atomic
  tmp_chain=$(mktemp "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem.XXXX")
  tmp_key=$(mktemp "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem.XXXX")

  cp -f "$SSL_CHAIN_ECC" "$tmp_chain"
  cp -f "$SSL_KEY_ECC" "$tmp_key"

  # set correct owner and mode on temp files (headscale:headscale, safe perms)
  chown headscale:headscale "$tmp_chain" "$tmp_key"
  chmod 0644 "$tmp_chain"
  chmod 0640 "$tmp_key"

  # move into place atomically
  mv -f "$tmp_chain" "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem"
  mv -f "$tmp_key" "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem"

  # ensure ACL grants only the caddy service read access (idempotent)
  setfacl -m u:caddy:r "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem" || true
  setfacl -m u:caddy:r "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem" || true

  # restart headscale so it picks up the new certs
  systemctl restart headscale || true

  # sanity: check caddy can read the final privkey before reloading
  if sudo -u caddy test -r "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem"; then
    log "[cert] caddy can read private key, validating and reloading caddy"
    /usr/bin/caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
  else
    echo "$(date -Iseconds) [cert][ERROR] caddy cannot read $SSL_DEPLOY_DIR_HEADSCALE/privkey.pem" >&2
    # print diagnostic info to help debugging
    ls -l "$SSL_DEPLOY_DIR_HEADSCALE"
    getfacl "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem" || true
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
