# --------------------------------------------------------------------
# mk/81_headscale.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Uses $(run_as_root) from mk/01_common.mk.
# - Calls with argv tokens, not quoted strings.
# - Operators escaped so they survive Make parsing.
# --------------------------------------------------------------------

SHELL := /bin/bash

.PHONY: ensure-run-as-root
ensure-run-as-root:
	@echo "[make] Ensuring run_as_root.sh is executable..."
	@chmod +x $(run_as_root)

.PHONY: rotate-noise-key
rotate-noise-key: ensure-run-as-root
	@echo "[make] Rotating Headscale Noise private key..."
	@$(run_as_root) systemctl stop headscale
	@$(run_as_root) rm -f /etc/headscale/noise_private.key
	@$(run_as_root) bash -c "umask 077; /usr/local/bin/headscale generate private-key > /etc/headscale/noise_private.key && chown headscale:headscale /etc/headscale/noise_private.key && chmod 600 /etc/headscale/noise_private.key"
	@$(run_as_root) systemctl start headscale
	@echo "[make] Noise private key rotated and Headscale restarted"
	@echo "[make] Validating Headscale service..."
	@$(run_as_root) bash -c "systemctl is-active --quiet headscale && echo '✔ Headscale service is running' || (echo '✘ Headscale service not active'; exit 1)"
	@$(run_as_root) bash -c "headscale version >/dev/null && echo '✔ Headscale CLI responsive' || (echo '✘ Headscale CLI failed to connect'; exit 1)"


.PHONY: headscale-logs
headscale-logs: ensure-run-as-root
	@echo "[make] Tailing headscale logs (Ctrl-C to exit)..."
	@$(run_as_root) journalctl -u headscale -f -n 100
