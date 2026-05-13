#!/usr/bin/env bash
set -euo pipefail

CN="${1:-}"
FORCE=0
if [ "${2:-}" = "--force" ]; then FORCE=1; fi

# Require non-empty CN
if [ -z "$CN" ]; then
  echo "Usage: $0 CN [--force]"
  exit 2
fi

# CN validation (restrict to a sane, predictable subset)
case "$CN" in
  *[!a-zA-Z0-9._-]*)
    echo "[err] CN contains illegal characters (allowed: a-zA-Z0-9._-)"
    exit 1
    ;;
esac

CA_KEY="/etc/ssl/private/ca/homelab_bardi_CA.key"
CA_PUB="/var/lib/ssl/canonical/ca.cer"
OUT_DIR="/etc/ssl/caddy/clients"

TMPDIR="$(mktemp -p /run -d homelab.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

KEY="$TMPDIR/client.key"
CSR="$TMPDIR/client.csr"
CRT="$TMPDIR/client.crt"
P12TMP="$TMPDIR/client.p12"

# Preconditions
if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_PUB" ]; then
  echo "[err] CA key or CA public cert missing. Run: make certs-deploy"
  exit 1
fi

sudo mkdir -p "$OUT_DIR"
sudo chmod 0750 "$OUT_DIR"

P12="${OUT_DIR}/${CN}.p12"
if [ -f "$P12" ] && [ "$FORCE" -ne 1 ]; then
  echo "[info] client p12 already exists: $P12 (use --force to overwrite)"
  exit 0
fi

# Generate client key + CSR
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$KEY"
openssl req -new -key "$KEY" \
  -subj "/CN=${CN}/O=bardi.ch/OU=users/emailAddress=${CN}@bardi.ch" \
  -out "$CSR"

# Sign CSR
sudo openssl x509 -req -in "$CSR" -CA "$CA_PUB" -CAkey "$CA_KEY" \
  -CAcreateserial -out "$CRT" -days 825 -sha256

sudo install -m 0644 "$CRT" "${OUT_DIR}/${CN}.crt"
sudo chown root:root "${OUT_DIR}/${CN}.crt"

# Create PKCS#12
if [ -n "${EXPORT_P12_PASS:-}" ]; then
  openssl pkcs12 -export -inkey "$KEY" -in "$CRT" -certfile "$CA_PUB" \
    -name "$CN" -out "$P12TMP" -passout env:EXPORT_P12_PASS
else
  openssl pkcs12 -export -inkey "$KEY" -in "$CRT" -certfile "$CA_PUB" \
    -name "$CN" -out "$P12TMP"
fi

sudo install -m 0640 "$P12TMP" "$P12"
sudo chown root:root "$P12"

# Remove CA serial file that -CAcreateserial may have created
CA_SRL="$(dirname "$CA_PUB")/$(basename "$CA_PUB").srl"
if [ -f "$CA_SRL" ]; then
  sudo rm -f "$CA_SRL" || true
fi
