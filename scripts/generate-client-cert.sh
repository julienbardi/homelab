#!/usr/bin/env bash
# scripts/generate-client-cert.sh CN [--force]
set -euo pipefail

CN="${1:-}"
FORCE=0
if [ "${2:-}" = "--force" ]; then FORCE=1; fi

if [ -z "$CN" ]; then
  echo "Usage: $0 CN [--force]"
  exit 2
fi

# Paths must match mk/50_certs.mk variables
CA_KEY="/etc/ssl/private/ca/homelab_bardi_CA.key"
CA_PUB="/var/lib/ssl/canonical/ca.cer"
OUT_DIR="/etc/ssl/caddy/clients"
TMPDIR="$(mktemp -d)"

# Preconditions
if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_PUB" ]; then
  echo "[err] CA key or CA public cert missing. Run: make certs-deploy"
  rm -rf "$TMPDIR"
  exit 1
fi

sudo mkdir -p "$OUT_DIR"
sudo chmod 0750 "$OUT_DIR"

P12="${OUT_DIR}/${CN}.p12"
if [ -f "$P12" ] && [ "$FORCE" -ne 1 ]; then
  echo "[info] client p12 already exists: $P12 (use --force to overwrite)"
  rm -rf "$TMPDIR"
  exit 0
fi

# Generate client key and CSR (EC P-256)
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$TMPDIR/${CN}.key"
openssl req -new -key "$TMPDIR/${CN}.key" -subj "/CN=${CN}/O=bardi.ch/OU=users/emailAddress=${CN}@bardi.ch" -out "$TMPDIR/${CN}.csr"

# Sign CSR with CA
sudo openssl x509 -req -in "$TMPDIR/${CN}.csr" -CA "$CA_PUB" -CAkey "$CA_KEY" -CAcreateserial -out "$TMPDIR/${CN}.crt" -days 825 -sha256

# Install PEM to canonical location so Makefile can always read it
sudo install -m 0644 "$TMPDIR/${CN}.crt" "${OUT_DIR}/${CN}.crt"
sudo chown root:root "${OUT_DIR}/${CN}.crt"
echo "[ok] client cert installed: ${OUT_DIR}/${CN}.crt"

# Create PKCS#12 (use EXPORT_P12_PASS non-interactively if provided; otherwise fall back to interactive)
if [ -n "${EXPORT_P12_PASS:-}" ]; then
  # non-interactive export using provided password (CI-friendly)
  openssl pkcs12 -export -inkey "$TMPDIR/${CN}.key" -in "$TMPDIR/${CN}.crt" -certfile "$CA_PUB" -name "$CN" -out "$TMPDIR/${CN}.p12" -passout env:EXPORT_P12_PASS
else
  # interactive fallback (preserves current behavior)
  openssl pkcs12 -export -inkey "$TMPDIR/${CN}.key" -in "$TMPDIR/${CN}.crt" -certfile "$CA_PUB" -name "$CN" -out "$TMPDIR/${CN}.p12"
fi

# Install p12
sudo install -m 0640 "$TMPDIR/${CN}.p12" "$P12"
sudo chown root:root "$P12"
echo "[ok] client p12 created: $P12"

# remove CA serial file that openssl -CAcreateserial may have created next to the CA file
CA_SRL="$(dirname "$CA_PUB")/$(basename "$CA_PUB").srl"
if [ -f "$CA_SRL" ]; then
  sudo rm -f "$CA_SRL" || true
fi

# Cleanup
rm -rf "$TMPDIR"

exit 0
