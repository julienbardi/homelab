#!/bin/bash
# ============================================================
# setup_headscale.sh
# ------------------------------------------------------------
# Install and configure Headscale (idempotent, safer defaults)
# Host: NAS / VPN node
# Responsibilities:
#   - Ensure headscale binary is installed to /usr/local/bin
#   - Deploy headscale.yaml and derp.yaml from repo (with install)
#   - Generate Noise private key if missing
#   - Ensure runtime dirs, DB and permissions
#   - Create a hardened systemd unit and enable/start service
# ============================================================

set -euo pipefail
IFS=$'\n\t'

# Resolve the directory this script lives in (works when invoked from any CWD).
# This resolves symlinks and yields an absolute path.
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"

# If your repo layout has scripts/ under the repo root, compute repo root:
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd)"

# load helper functions (log, run_as_root, etc.)
HOMELAB_ENV="${REPO_ROOT}/config/homelab.env"
COMMON_SH="${REPO_ROOT}/scripts/common.sh"

if [ -f "${HOMELAB_ENV}" ]; then
  # shellcheck disable=SC1090
  source "${HOMELAB_ENV}"
else
  echo "Missing ${HOMELAB_ENV}; run this script from the repository root." >&2
  exit 1
fi

if [ -f "${COMMON_SH}" ]; then
  # shellcheck disable=SC1090
  source "${COMMON_SH}"
else
  echo "Missing ${COMMON_SH}; run this script from the repository root." >&2
  exit 1
fi

# Ensure run_as_root helper is available (fallback to sudo)
if ! command -v run_as_root >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
	run_as_root() { sudo "$@"; }
  else
	echo "run_as_root helper not found and sudo unavailable; aborting" >&2
	exit 1
  fi
fi

SERVICE_NAME="headscale"
CONFIG_DIR="/etc/headscale"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
DERP_FILE="${CONFIG_DIR}/derp.yaml"
SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
REPO_CONFIG="${REPO_ROOT}/config/headscale.yaml"
REPO_DERP="${REPO_ROOT}/config/derp.yaml"

# install locations and runtime user
HEADSCALE_BIN="/usr/local/bin/headscale"
HEADSCALE_USER="headscale"
DB_DIR="/var/lib/headscale"
DB_FILE="${DB_DIR}/db.sqlite"
RUNTIME_DIR="/var/run/headscale"

# --- Prerequisite checks ---
log "Starting Headscale setup..."

if run_as_root ip link add dev wg-test type wireguard 2>/dev/null; then
  run_as_root ip link del dev wg-test 2>/dev/null
  log "WireGuard kernel support detected"
else
  log "⚠️ WireGuard kernel module not available; data-plane features may degrade"
fi

# --- Ensure runtime user exists ---
if ! id -u "${HEADSCALE_USER}" >/dev/null 2>&1; then
  log "Creating system user ${HEADSCALE_USER}"
  run_as_root useradd --system --no-create-home --shell /usr/sbin/nologin "${HEADSCALE_USER}" || true
else
  log "User ${HEADSCALE_USER} already exists"
fi

# --- Verify Headscale binary (preinstalled, authoritative path) ---
HS_BIN="/usr/local/bin/headscale"

log "Checking for headscale binary at ${HS_BIN}"
if [ ! -x "${HS_BIN}" ]; then
  log "ERROR: ${HS_BIN} not found or not executable"
  log "Install the official Headscale binary before running this script"
  exit 1
fi

log "Found headscale binary: $(${HS_BIN} version 2>/dev/null)"

# --- Deploy configs from repo ---
log "Deploying Headscale config files"
run_as_root install -d -o root -g "${HEADSCALE_USER}" -m 0750 "${CONFIG_DIR}"
if [ -f "${REPO_CONFIG}" ]; then
  run_as_root install -m 0644 "${REPO_CONFIG}" "${CONFIG_FILE}"
  log "Installed ${REPO_CONFIG} -> ${CONFIG_FILE}"
fi

if [ -f "${REPO_DERP}" ]; then
  run_as_root install -m 0644 "${REPO_DERP}" "${DERP_FILE}"
  log "Installed ${REPO_DERP} -> ${DERP_FILE}"
else
  if [ ! -f "${DERP_FILE}" ]; then
	run_as_root bash -c "
printf '%s\n' \
  'regions:' \
  '  1:' \
  '    region_id: 1' \
  '    region_code: \"global\"' \
  '    region_name: \"Tailscale Global DERPs\"' \
  '    nodes:' \
  '      - name: \"derp1\"' \
  '        region_id: 1' \
  '        host_name: \"derp1.tailscale.com\"' \
  '        stun: true' \
> '${DERP_FILE}'
"
	log "Created minimal DERP file at ${DERP_FILE}"
  fi
fi

# Ensure config references DERP file
if [ -f "${CONFIG_FILE}" ] && ! grep -q "derp:" "${CONFIG_FILE}"; then
  run_as_root bash -c "
printf '\n%s\n' \
  'derp:' \
  '  paths:' \
  '    - ${DERP_FILE}' \
>> '${CONFIG_FILE}'
"
fi

log "Fixing Headscale config file permissions"
run_as_root chown root:"${HEADSCALE_USER}" "${CONFIG_FILE}"
run_as_root chmod 640 "${CONFIG_FILE}"

if [ -f "${DERP_FILE}" ]; then
  run_as_root chown root:"${HEADSCALE_USER}" "${DERP_FILE}"
  run_as_root chmod 640 "${DERP_FILE}"
fi

if ! "${HS_BIN}" version >/dev/null 2>&1; then
  log "ERROR: Headscale cannot read config file"
  exit 1
fi

# --- Ensure DB directory and file ---
log "Ensuring DB directory ${DB_DIR} and file ${DB_FILE}"
run_as_root install -d -o "${HEADSCALE_USER}" -g "${HEADSCALE_USER}" -m 0770 "${DB_DIR}"
if [ ! -f "${DB_FILE}" ]; then
  run_as_root touch "${DB_FILE}"
  log "Created DB file ${DB_FILE}"
fi
run_as_root chmod 660 "${DB_FILE}" || true
run_as_root rm -f "${DB_DIR}"/db.sqlite-* || true

# --- Runtime directory and socket cleanup ---
log "Preparing runtime directory ${RUNTIME_DIR}"
run_as_root install -d -o "${HEADSCALE_USER}" -g "${HEADSCALE_USER}" -m 0770 "${RUNTIME_DIR}"
if [ -S "${RUNTIME_DIR}/headscale.sock" ]; then
  run_as_root rm -f "${RUNTIME_DIR}"/headscale.sock
  log "Removed stale socket ${RUNTIME_DIR}/headscale.sock"
fi

# --- Noise private key generation ---
if [ ! -f "${CONFIG_DIR}/noise_private.key" ]; then
  run_as_root --preserve env HS_BIN="${HS_BIN}" CONFIG_DIR="${CONFIG_DIR}" \
	bash -s _ "$HS_BIN" "$CONFIG_DIR" <<'INNER'
umask 077
exec "$1" generate private-key > "$2/noise_private.key"
INNER
  if [ -f "${CONFIG_DIR}/noise_private.key" ]; then
	log "Noise private key created at ${CONFIG_DIR}/noise_private.key"
	run_as_root chown "${HEADSCALE_USER}":"${HEADSCALE_USER}" "${CONFIG_DIR}/noise_private.key"
	run_as_root chmod 600 "${CONFIG_DIR}/noise_private.key"
  else
	log "ERROR: failed to generate Noise private key"
  fi
fi

# --- Systemd unit ---
log "Writing systemd unit to ${SYSTEMD_UNIT}"
run_as_root bash -c "
printf '%s\n' \
  '[Unit]' \
  'Description=Headscale coordination server' \
  'After=network.target' \
  '' \
  '[Service]' \
  'ExecStart=${HS_BIN} serve --config ${CONFIG_FILE}' \
  'WorkingDirectory=${CONFIG_DIR}' \
  'User=${HEADSCALE_USER}' \
  'Group=${HEADSCALE_USER}' \
  'Restart=on-failure' \
  'RestartSec=5' \
  'LimitNOFILE=65536' \
  'RuntimeDirectory=headscale' \
  'RuntimeDirectoryMode=0770' \
  'PrivateTmp=yes' \
  'ProtectSystem=full' \
  'ProtectHome=yes' \
  'NoNewPrivileges=yes' \
  'PrivateDevices=yes' \
  'CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE' \
  'AmbientCapabilities=' \
  '' \
  '[Install]' \
  'WantedBy=multi-user.target' \
> '${SYSTEMD_UNIT}'
"
run_as_root chmod 0644 "${SYSTEMD_UNIT}"

# Ensure systemd drop-in allows headscale to use /etc/headscale and exports the config path
run_as_root install -d -o root -g root -m 0755 "/etc/systemd/system/${SERVICE_NAME}.service.d"

run_as_root bash -c "
printf '%s\n' \
  '[Service]' \
  'Environment=HEADSCALE_CONFIG=${CONFIG_FILE}' \
  'ReadWritePaths=${CONFIG_DIR}' \
> '/etc/systemd/system/${SERVICE_NAME}.service.d/override.conf'
"
run_as_root chmod 0644 "/etc/systemd/system/${SERVICE_NAME}.service.d/override.conf"

# --- Reload systemd and enable/start service ---
log "Reloading systemd and enabling ${SERVICE_NAME}"
run_as_root systemctl daemon-reload
run_as_root systemctl enable "${SERVICE_NAME}"

if sudo -u "${HEADSCALE_USER}" "${HS_BIN}" configtest -c "${CONFIG_FILE}" >/dev/null 2>&1; then
  run_as_root systemctl restart "${SERVICE_NAME}"
else
  log "ERROR: headscale configtest failed; not restarting service"
fi

# --- Final checks ---
log "Headscale version: $(${HS_BIN} version 2>/dev/null || echo 'unknown')"

log "Headscale setup complete. Verify with: sudo systemctl status ${SERVICE_NAME}; sudo journalctl -u ${SERVICE_NAME} -n 200"