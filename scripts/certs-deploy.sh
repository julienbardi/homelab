#!/bin/sh
set -e

SSL_CANONICAL_DIR="/var/lib/ssl/canonical"
CA_PUB="/etc/ssl/certs/homelab_bardi_CA.pem"
CANON_CA="${SSL_CANONICAL_DIR}/ca.cer"
CADDY_DEPLOY_DIR="/etc/ssl/caddy"

CONF_FORCE="${CONF_FORCE:-0}"
export CONF_FORCE

echo "[certs] deploying CA public cert to canonical store and caddy"

mkdir -p "$SSL_CANONICAL_DIR"
install -m 0644 "$CA_PUB" "$CANON_CA"
chown root:root "$CANON_CA"

mkdir -p "$CADDY_DEPLOY_DIR"
install -m 0644 "$CANON_CA" "$CADDY_DEPLOY_DIR/homelab_bardi_CA.pem"
chown root:root "$CADDY_DEPLOY_DIR/homelab_bardi_CA.pem"

echo "[certs] deployed to $CANON_CA and $CADDY_DEPLOY_DIR/homelab_bardi_CA.pem"
