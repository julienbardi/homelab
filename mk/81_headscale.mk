# --------------------------------------------------------------------
# mk/81_headscale.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Uses $(run_as_root) from mk/01_common.mk.
# - Calls with argv tokens, not quoted strings.
# - Operators escaped so they survive Make parsing.
# --------------------------------------------------------------------

SHELL := /bin/bash

HEADSCALE_BIN := /usr/local/bin/headscale
HEADSCALE_URL := https://github.com/juanfont/headscale/releases/latest/download/headscale-linux-amd64

.PHONY: ensure-run-as-root
ensure-run-as-root:
	@echo "[make] Ensuring run_as_root.sh is executable..."
	@chmod +x $(run_as_root)

# --------------------------------------------------------------------
# Ensure Headscale binary is installed
# --------------------------------------------------------------------
.PHONY: headscale-bin
headscale-bin: ensure-run-as-root
	@if [ -x "$(HEADSCALE_BIN)" ]; then \
		echo "[make] Headscale binary already present"; \
	else \
		echo "[make] Installing Headscale binary"; \
		$(run_as_root) curl -fsSL "$(HEADSCALE_URL)" -o "$(HEADSCALE_BIN)"; \
		$(run_as_root) chmod 0755 "$(HEADSCALE_BIN)"; \
	fi

# --------------------------------------------------------------------
# Rotate Noise private key
# --------------------------------------------------------------------
.PHONY: rotate-noise-key
rotate-noise-key: ensure-run-as-root headscale-bin
	@echo "[make] Rotating Headscale Noise private key..."
	@$(run_as_root) systemctl stop headscale
	@$(run_as_root) rm -f /etc/headscale/noise_private.key
	@$(run_as_root) bash -c "umask 077; /usr/local/bin/headscale generate private-key > /etc/headscale/noise_private.key && chown headscale:headscale /etc/headscale/noise_private.key && chmod 600 /etc/headscale/noise_private.key"
	@$(run_as_root) systemctl start headscale
	@echo "[make] Noise private key rotated and Headscale restarted"
	@echo "[make] Validating Headscale service..."
	@$(run_as_root) bash -c "systemctl is-active --quiet headscale && echo '✔ Headscale service is running' || (echo '✘ Headscale service not active'; exit 1)"
	@$(run_as_root) bash -c "headscale version >/dev/null && echo '✔ Headscale CLI responsive' || (echo '✘ Headscale CLI failed to connect'; exit 1)"

# --------------------------------------------------------------------
# Tail Headscale logs
# --------------------------------------------------------------------
.PHONY: headscale-logs
headscale-logs: ensure-run-as-root
	@echo "[make] Tailing headscale logs (Ctrl-C to exit)..."
	@$(run_as_root) journalctl -u headscale -f -n 100
