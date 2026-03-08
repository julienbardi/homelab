#!/usr/bin/env bash
# generate-client-cert.sh CN [--force]
set -euo pipefail

CN="${1:-}"
FORCE=0
if [ "${2:-}" = "--force" ]; then FORCE=1; fi

if [ -z "$CN" ]; then
    echo "Usage: $0 CN [--force]"
    exit 2
fi

CA_KEY="/jffs/ssl/private/ca/homelab_bardi_CA.key"
CA_PUB="/jffs/ssl/canonical/ca.cer"
OUT_DIR="/jffs/ssl/caddy/clients"

TMPDIR="/tmp/certgen-${CN}"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

# Preconditions
if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_PUB" ]; then
    echo "[err] CA key or CA public cert missing. Run: make certs-deploy"
    rm -rf "$TMPDIR"
    exit 1
fi

mkdir -p "$OUT_DIR"
chmod 0750 "$OUT_DIR"

P12="${OUT_DIR}/${CN}.p12"
if [ -f "$P12" ] && [ "$FORCE" -ne 1 ]; then
    echo "[info] client p12 already exists: $P12 (use --force to overwrite)"
    rm -rf "$TMPDIR"
    exit 0
fi

# Generate client key and CSR (EC P-256)
openssl genpkey \
    -algorithm EC \
    -pkeyopt ec_paramgen_curve:P-256 \
    -out "$TMPDIR/${CN}.key"

openssl req -new \
    -key "$TMPDIR/${CN}.key" \
    -subj "/CN=${CN}/O=bardi.ch/OU=users/emailAddress=${CN}@bardi.ch" \
    -out "$TMPDIR/${CN}.csr"

# Sign CSR with CA
openssl x509 -req \
    -in "$TMPDIR/${CN}.csr" \
    -CA "$CA_PUB" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$TMPDIR/${CN}.crt" \
    -days 825 \
    -sha256

# Install PEM
cp "$TMPDIR/${CN}.crt" "${OUT_DIR}/${CN}.crt"
chmod 0644 "${OUT_DIR}/${CN}.crt"
echo "[ok] client cert installed: ${OUT_DIR}/${CN}.crt"

# Create PKCS#12
if [ -n "${EXPORT_P12_PASS:-}" ]; then
    openssl pkcs12 -export \
        -inkey "$TMPDIR/${CN}.key" \
        -in "$TMPDIR/${CN}.crt" \
        -certfile "$CA_PUB" \
        -name "$CN" \
        -out "$TMPDIR/${CN}.p12" \
        -passout env:EXPORT_P12_PASS
else
    openssl pkcs12 -export \
        -inkey "$TMPDIR/${CN}.key" \
        -in "$TMPDIR/${CN}.crt" \
        -certfile "$CA_PUB" \
        -name "$CN" \
        -out "$TMPDIR/${CN}.p12"
fi

# Install p12
cp "$TMPDIR/${CN}.p12" "$P12"
chmod 0640 "$P12"
echo "[ok] client p12 created: $P12"

# Remove CA serial file created by -CAcreateserial
CA_SRL="$(dirname "$CA_PUB")/$(basename "$CA_PUB").srl"
[ -f "$CA_SRL" ] && rm -f "$CA_SRL" || true

rm -rf "$TMPDIR"
exit 0
