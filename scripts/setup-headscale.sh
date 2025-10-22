#!/usr/bin/env bash
#
# setup_headscale.sh — Automated Headscale installation and configuration script
set -euo pipefail

INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/headscale.service"
CONFIG_DIR="/etc/headscale"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
ARCH_DL="amd64"

HOST="nas.bardi.ch"
PORT=8443      # HTTPS control plane / web admin API
GRPC_PORT=""   # leave empty to disable gRPC, or set to e.g. 50443

CERT_DIR="/etc/headscale/certs"
CERT_FULLCHAIN="$CERT_DIR/fullchain.pem"
CERT_KEY="$CERT_DIR/privkey.pem"

SCRIPT_VERSION="v1.3"

TMP_CERT="/tmp/headscale-cert.$$"
trap 'rm -f "$TMP_CERT"' EXIT

log() { echo -e "$*"; }

# === [1] PREREQUISITES ===
log "🔐 [1] Checking prerequisites"
for bin in curl jq openssl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    log "❌ Missing required tool: $bin"
    exit 1
  fi
done
log "✅ All required tools present"

# === [2] CERTIFICATE CHECK ===
log "🔍 [2] Checking certificate files"
[[ -f "$CERT_FULLCHAIN" ]] || { log "❌ Missing $CERT_FULLCHAIN"; exit 1; }
[[ -f "$CERT_KEY" ]] || { log "❌ Missing $CERT_KEY"; exit 1; }

if ! openssl x509 -in "$CERT_FULLCHAIN" -noout -dates >"$TMP_CERT" 2>/dev/null; then
  log "❌ Could not parse certificate"
  exit 1
fi
notAfter=$(grep notAfter "$TMP_CERT" | cut -d= -f2-)
expiry_epoch=$(date -d "$notAfter" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$notAfter" +%s)
now_epoch=$(date +%s)
[[ "$expiry_epoch" -le "$now_epoch" ]] && { log "❌ Certificate expired ($notAfter)"; exit 1; }
log "✅ Certificate valid until: $notAfter"

# === [3] FETCH RELEASE INFO ===
log "📦 [3] Checking Headscale release"

LATEST=$(curl -s https://api.github.com/repos/juanfont/headscale/releases/latest | jq -r .tag_name)
if [[ -z "$LATEST" || "$LATEST" == "null" ]]; then
  LATEST=$(curl -s https://api.github.com/repos/juanfont/headscale/releases \
    | jq -r 'try (map(select(.prerelease == false and .draft == false))[0].tag_name) // empty')
fi
if [[ -z "$LATEST" || "$LATEST" == "null" ]]; then
  log "⚠️ Could not determine latest release from API, falling back to v0.26.1"
  LATEST="v0.26.1"
fi

INSTALLED="$($INSTALL_DIR/headscale version 2>/dev/null || echo none)"
LATEST_CLEAN="${LATEST#v}"
log "ℹ️ Latest release: $LATEST"
log "ℹ️ Installed version: $INSTALLED"

# === [4] INSTALL/UPDATE HEADSCALE ===
if [[ "$INSTALLED" != "$LATEST_CLEAN" ]]; then
  log "⬇️ Installing Headscale $LATEST"
  TMPDIR="$(mktemp -d)"
  cd "$TMPDIR"

  ASSET_URL=$(curl -s "https://api.github.com/repos/juanfont/headscale/releases/tags/${LATEST}" \
    | jq -r 'try (.assets[]? | select(.name | test("linux_amd64$")) | .browser_download_url) // empty')

  if [[ -z "$ASSET_URL" ]]; then
    ASSET_URL="https://github.com/juanfont/headscale/releases/download/${LATEST}/headscale_${LATEST#v}_linux_amd64"
  fi

  if [[ -z "$ASSET_URL" ]]; then
    log "❌ Could not determine asset URL for $LATEST"
    exit 1
  fi

  log "⬇️ Downloading asset: $ASSET_URL"
  curl -L -o headscale "$ASSET_URL"
  chmod +x headscale
  sudo mv headscale "$INSTALL_DIR/headscale"
  sudo chmod 755 "$INSTALL_DIR/headscale"
  log "✅ Headscale $LATEST installed"
else
  log "✅ Headscale already up to date ($INSTALLED)"
fi

# === [5] CONFIGURATION ===
log "🔧 [5] Ensuring configuration"
[[ -d "$CONFIG_DIR" ]] || { sudo mkdir -p "$CONFIG_DIR"; sudo chown root:root "$CONFIG_DIR"; }

EXPECTED_CONFIG=$(cat <<EOF
server_url: https://${HOST}:${PORT}
listen_addr: :${PORT}
private_key_path: ${CONFIG_DIR}/private.key
noise:
  private_key_path: ${CONFIG_DIR}/noise_private.key
tls_cert_path: ${CERT_FULLCHAIN}
tls_key_path: ${CERT_KEY}

database:
  type: sqlite
  sqlite:
    path: ${CONFIG_DIR}/db.sqlite

dns:
  magic_dns: false
  override_local_dns: true
  nameservers:
    global:  
      - 100.64.0.3   # NAS over Tailscale IPv4
      - 1.1.1.1      # Fallback resolver (optional but recommended)
#dns:
#  magic_dns: true
#  base_domain: bardi.ch
#  override_local_dns: true
#  nameservers:
#    global:
#      - 192.168.50.4                         # NAS IPv4 (static)
#      - 2a01:8b81:4800:9c00::50              # NAS IPv6 (manually assigned static address)

derp:
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  auto_update: true

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48

grpc_listen_addr: $([[ -n "$GRPC_PORT" ]] && echo ":$GRPC_PORT" || echo "\"\"")
EOF
)

if [[ ! -f "$CONFIG_FILE" ]]; then
  log "📝 Creating default config.yaml (new)"
  echo "$EXPECTED_CONFIG" | sudo tee "$CONFIG_FILE" >/dev/null
else
  CURRENT_CONFIG=$(sudo cat "$CONFIG_FILE")
  if [[ "$CURRENT_CONFIG" != "$EXPECTED_CONFIG" ]]; then
    log "⚠️ Config file differs from expected — overwriting with hardened default"
    echo "$EXPECTED_CONFIG" | sudo tee "$CONFIG_FILE" >/dev/null
  else
    log "✅ Config file matches expected template — leaving untouched"
  fi
fi

# === [6] SYSTEMD SERVICE ===
log "🔄 [6] Ensuring systemd service"
if [[ ! -f "$SERVICE_FILE" ]]; then
  sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Headscale coordination server
After=network.target

[Service]
ExecStart=$INSTALL_DIR/headscale serve --config $CONFIG_FILE
Restart=on-failure
User=root
WorkingDirectory=$CONFIG_DIR

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reexec
  sudo systemctl enable headscale
  log "✅ Service created and enabled"
else
  log "ℹ️ Service file already exists, leaving untouched"
fi

# === [7] RESTART SERVICE ===
log "🔄 [7] Restarting Headscale"
sudo systemctl restart headscale
log "✅ Headscale service restarted"

# === [8] FOOTER ===
TIMESTAMP="$(date +'%F %T')"
log "🏁 Setup complete — $SCRIPT_VERSION @ $TIMESTAMP"
log "ℹ️ To generate a client join key:"
log "    sudo ./headscale-keys.sh new <machine>"
