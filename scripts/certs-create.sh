#!/bin/sh
set -e

CA_KEY="/etc/ssl/private/ca/homelab_bardi_CA.key"
CA_PUB="/etc/ssl/certs/homelab_bardi_CA.pem"

echo "[certs] ensure CA private key + public cert exist"

if [ -f "$CA_KEY" ] && [ -f "$CA_PUB" ]; then
  echo "[certs] CA already exists: $CA_PUB"
else
  mkdir -p /etc/ssl/private/ca
  chmod 700 /etc/ssl/private/ca

  echo "[certs] generating CA private key $CA_KEY"
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out "$CA_KEY"
  chmod 0600 "$CA_KEY"

  echo "[certs] generating CA public cert $CA_PUB"
  openssl req -x509 -new -key "$CA_KEY" -days 3650 -sha256 \
    -subj "/CN=homelab-bardi-CA/O=bardi.ch/OU=homelab" -out "$CA_PUB"
  chmod 0644 "$CA_PUB"
fi
