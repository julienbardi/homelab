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

# load helper functions (log, run_as_root, etc.)
source "/home/julie/src/homelab/scripts/common.sh"

SERVICE_NAME="headscale"
CONFIG_DIR="/etc/headscale"
CONFIG_FILE="${CONFIG_DIR}/headscale.yaml"
DERP_FILE="${CONFIG_DIR}/derp.yaml"
SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
REPO_CONFIG="/home/julie/src/homelab/config/headscale.yaml"
REPO_DERP="/home/julie/src/homelab/config/derp.yaml"
NAS_IP="10.89.12.4"
UNBOUND_IP="${NAS_IP}"   # Unbound runs locally on NAS

# install locations and runtime user
GOBIN="/usr/local/bin"
HEADSCALE_BIN="${GOBIN}/headscale"
HEADSCALE_USER="headscale"
DB_DIR="/var/lib/headscale"
DB_FILE="${DB_DIR}/db.sqlite"
RUNTIME_DIR="/var/run/headscale"

# --- Prerequisite checks ---
log "Starting Headscale setup..."

if ! command -v go >/dev/null 2>&1; then
	log "WARNING: Go not found in PATH. The script will continue but headscale install may fail."
fi

if ! modprobe wireguard >/dev/null 2>&1; then
	log "WARNING: WireGuard kernel module not available. Headscale may run in degraded mode for some features."
fi

# --- Ensure runtime user exists ---
if ! id -u "${HEADSCALE_USER}" >/dev/null 2>&1; then
	log "Creating system user ${HEADSCALE_USER}"
	run_as_root useradd --system --no-create-home --shell /usr/sbin/nologin "${HEADSCALE_USER}" || true
else
	log "User ${HEADSCALE_USER} already exists"
fi

# --- Install Headscale binary to a known location ---
log "Installing headscale binary to ${HEADSCALE_BIN} (if missing)"
if [ ! -x "${HEADSCALE_BIN}" ]; then
	if command -v go >/dev/null 2>&1; then
		log "Running 'go install' to place headscale in ${GOBIN}"
		# ensure GOBIN exists and is writable by sudo when needed
		run_as_root mkdir -p "${GOBIN}"
		# install; tolerate failure but log it
		if GOBIN="${GOBIN}" go install github.com/juanfont/headscale/cmd/headscale@latest; then
			log "headscale installed to ${GOBIN}"
		else
			log "ERROR: go install failed; headscale binary not installed"
		fi
	else
		log "ERROR: go not available; cannot install headscale automatically"
	fi
else
	log "headscale binary already present at ${HEADSCALE_BIN}"
fi

# --- Deploy configs from repo (atomic, idempotent) ---
log "Deploying Headscale config files"
run_as_root mkdir -p "${CONFIG_DIR}"
if [ -f "${REPO_CONFIG}" ]; then
	run_as_root install -m 0644 "${REPO_CONFIG}" "${CONFIG_FILE}"
	log "Installed ${REPO_CONFIG} -> ${CONFIG_FILE}"
else
	log "WARNING: ${REPO_CONFIG} not found in repo; leaving existing ${CONFIG_FILE} if present"
fi

if [ -f "${REPO_DERP}" ]; then
	run_as_root install -m 0644 "${REPO_DERP}" "${DERP_FILE}"
	log "Installed ${REPO_DERP} -> ${DERP_FILE}"
else
	log "DERP config not found in repo; creating a minimal DERP file if missing"
	if [ ! -f "${DERP_FILE}" ]; then
		run_as_root tee "${DERP_FILE}" > /dev/null <<'EOF'
regions:
  1:
	region_id: 1
	region_code: "global"
	region_name: "Tailscale Global DERPs"
	nodes:
	  - name: "derp1"
		region_id: 1
		host_name: "derp1.tailscale.com"
		stun: true
EOF
		log "Created minimal DERP file at ${DERP_FILE}"
	fi
fi

# Ensure config references DERP file (idempotent append)
if [ -f "${CONFIG_FILE}" ] && ! grep -q "derp:" "${CONFIG_FILE}"; then
	log "Adding DERP reference to ${CONFIG_FILE}"
	run_as_root tee -a "${CONFIG_FILE}" > /dev/null <<EOF

derp:
  paths:
	- ${DERP_FILE}
EOF
else
	log "DERP reference already present in ${CONFIG_FILE} or config missing"
fi

# --- Ensure DB directory and file exist with correct permissions ---
log "Ensuring DB directory ${DB_DIR} and file ${DB_FILE}"
run_as_root mkdir -p "${DB_DIR}"
if [ ! -f "${DB_FILE}" ]; then
	run_as_root touch "${DB_FILE}"
	log "Created DB file ${DB_FILE}"
fi
run_as_root chown -R "${HEADSCALE_USER}:${HEADSCALE_USER}" "${DB_DIR}"
run_as_root chmod 660 "${DB_FILE}" || true
run_as_root chmod 770 "${DB_DIR}" || true
# remove stale sqlite journal files if any
run_as_root rm -f "${DB_DIR}/db.sqlite-"* || true

# --- Runtime directory and socket cleanup ---
log "Preparing runtime directory ${RUNTIME_DIR}"
run_as_root mkdir -p "${RUNTIME_DIR}"
run_as_root chown "${HEADSCALE_USER}:${HEADSCALE_USER}" "${RUNTIME_DIR}"
run_as_root chmod 770 "${RUNTIME_DIR}"
if [ -S "${RUNTIME_DIR}/headscale.sock" ]; then
	run_as_root rm -f "${RUNTIME_DIR}/headscale.sock"
	log "Removed stale socket ${RUNTIME_DIR}/headscale.sock"
fi

# --- Noise private key generation (only if binary present) ---
if command -v "${HEADSCALE_BIN}" >/dev/null 2>&1 || command -v headscale >/dev/null 2>&1; then
	HS_BIN="$(command -v headscale || echo "${HEADSCALE_BIN}")"
	if [ ! -f "${CONFIG_DIR}/noise_private.key" ]; then
		log "Generating Noise private key..."
		if "${HS_BIN}" generate noise-key -o "${CONFIG_DIR}/noise_private.key"; then
			log "Noise private key created at ${CONFIG_DIR}/noise_private.key"
			run_as_root chown "${HEADSCALE_USER}:${HEADSCALE_USER}" "${CONFIG_DIR}/noise_private.key" || true
			run_as_root chmod 600 "${CONFIG_DIR}/noise_private.key" || true
		else
			log "ERROR: Failed to generate Noise private key"
		fi
	else
		log "Noise private key already exists, skipping generation"
	fi
else
	log "WARNING: headscale binary not found; skipping noise-key generation"
fi

# --- Systemd unit (hardened, idempotent write) ---
log "Writing systemd unit to ${SYSTEMD_UNIT}"
run_as_root tee "${SYSTEMD_UNIT}" > /dev/null <<EOF
[Unit]
Description=Headscale coordination server
After=network.target

[Service]
ExecStart=${HEADSCALE_BIN} serve
WorkingDirectory=${CONFIG_DIR}
User=${HEADSCALE_USER}
Group=${HEADSCALE_USER}
Restart=on-failure
RuntimeDirectory=headscale
RuntimeDirectoryMode=0770
PrivateTmp=yes
ProtectSystem=full
ProtectHome=yes
NoNewPrivileges=yes
AmbientCapabilities=
Environment=HEADSCALE_CONFIG=${CONFIG_FILE}

[Install]
WantedBy=multi-user.target
EOF

# --- Reload systemd and enable/start service ---
log "Reloading systemd and enabling ${SERVICE_NAME}"
run_as_root systemctl daemon-reload
run_as_root systemctl enable "${SERVICE_NAME}"
if run_as_root systemctl restart "${SERVICE_NAME}"; then
	log "Headscale service restarted successfully"
else
	log "ERROR: Failed to start/restart Headscale service; check journalctl -u ${SERVICE_NAME}"
fi

# --- Final checks and info ---
if command -v "${HEADSCALE_BIN}" >/dev/null 2>&1 || command -v headscale >/dev/null 2>&1; then
	HS_BIN="$(command -v headscale || echo "${HEADSCALE_BIN}")"
	log "Headscale version: $(${HS_BIN} version 2>/dev/null || echo 'unknown')"
else
	log "Headscale binary not available at ${HEADSCALE_BIN}; please check installation"
fi

log "Headscale setup complete. Verify with: sudo systemctl status ${SERVICE_NAME} and sudo journalctl -u ${SERVICE_NAME} -n 200"
