#!/bin/sh
# certs-deploy.sh — deploy CA public cert (idempotent)
set -e

CA_PUB="/jffs/ssl/certs/homelab_bardi_CA.pem"
SSL_CANONICAL_DIR="/jffs/ssl/canonical"
CANON_CA="${SSL_CANONICAL_DIR}/ca.cer"
CADDY_DEPLOY_DIR="/jffs/ssl/caddy"

log() {
    echo "[certs] $@" >&2
}

if [ ! -f "$CA_PUB" ]; then
    log "ERROR: CA public cert missing: $CA_PUB"
    exit 1
fi

log "deploying CA public cert"

# Canonical store
mkdir -p "$SSL_CANONICAL_DIR"
chmod 0755 "$SSL_CANONICAL_DIR"
cp "$CA_PUB" "$CANON_CA"
chmod 0644 "$CANON_CA"

# Caddy trust directory
mkdir -p "$CADDY_DEPLOY_DIR"
chmod 0755 "$CADDY_DEPLOY_DIR"
cp "$CANON_CA" "$CADDY_DEPLOY_DIR/homelab_bardi_CA.pem"
chmod 0644 "$CADDY_DEPLOY_DIR/homelab_bardi_CA.pem"

log "CA public cert deployed successfully"
exit 0
