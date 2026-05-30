#!/bin/sh
# certs-create.sh — create internal CA (idempotent)
set -e

export RANDFILE=/dev/null

CA_KEY="/jffs/ssl/private/ca/homelab_bardi_CA.key"
CA_PUB="/jffs/ssl/certs/homelab_bardi_CA.pem"

echo "[certs] ensure internal CA exists"

# If both key and cert exist, we are done
if [ -f "$CA_KEY" ] && [ -f "$CA_PUB" ]; then
    echo "[certs] CA already exists: $CA_PUB"
    exit 0
fi

# Prepare directories
mkdir -p /jffs/ssl/private/ca
chmod 0700 /jffs/ssl/private/ca

mkdir -p /jffs/ssl/certs
chmod 0755 /jffs/ssl/certs

# Generate CA private key (EC P-384)
echo "[certs] generating CA private key"
openssl genpkey \
    -algorithm EC \
    -pkeyopt ec_paramgen_curve:P-384 \
    -out "$CA_KEY"

chmod 0600 "$CA_KEY"

# Generate self-signed CA certificate
echo "[certs] generating CA public certificate"
openssl req -x509 -new \
    -key "$CA_KEY" \
    -days 3650 \
    -sha256 \
    -subj "/CN=homelab-bardi-CA/O=bardi.ch/OU=homelab" \
    -out "$CA_PUB"

chmod 0644 "$CA_PUB"

echo "[certs] CA created successfully"
exit 0
