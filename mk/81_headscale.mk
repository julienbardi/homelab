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
HEADSCALE_URL := https://github.com/juanfont/headscale/releases/download/v0.28.0-beta.1/headscale_0.28.0-beta.1_linux_amd64

# --------------------------------------------------------------------
# Ensure Headscale binary is installed
# --------------------------------------------------------------------
.PHONY: headscale-bin
headscale-bin: ensure-run-as-root
	@if [ -x "$(HEADSCALE_BIN)" ]; then \
		echo "[make] ✅ Headscale binary already present"; \
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

# --------------------------------------------------------------------
# Headscale provisioning prerequisites (parallel-safe)
# --------------------------------------------------------------------
.PHONY: headscale-prereqs
headscale-prereqs: \
	harden-groups \
	config/headscale.yaml \
	config/derp.yaml \
	deploy-headscale \
	headscale-bin \
	headscale-systemd

# --------------------------------------------------------------------
# Headscale orchestration (serialized)
# --------------------------------------------------------------------
.PHONY: headscale
headscale: headscale-prereqs
	@echo "[make] Restarting Headscale..."
	@$(run_as_root) systemctl restart headscale
	@$(MAKE) headscale-acls
	@$(MAKE) headscale-verify
	@echo ""
	@echo "[headscale] ℹ️  For detailed status:"
	@echo "           sudo systemctl status headscale"
	@echo "           sudo journalctl -u headscale -n 200"
	@echo ""

# --------------------------------------------------------------------
# Install Headscale systemd unit (static, declarative)
# --------------------------------------------------------------------
.PHONY: headscale-systemd
headscale-systemd: ensure-run-as-root
	@$(run_as_root) install -m 0644 config/systemd/headscale.service /etc/systemd/system/headscale.service
	@$(run_as_root) install -d -m 0755 /etc/systemd/system/headscale.service.d
	@$(run_as_root) install -m 0644 config/systemd/headscale.service.d/override.conf /etc/systemd/system/headscale.service.d/override.conf
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable headscale

# --------------------------------------------------------------------
# Headscale verification (post-deploy checks)
# --------------------------------------------------------------------


# --------------------------------------------------------------------
# Atomic Headscale verification tests (parallel-safe)
# --------------------------------------------------------------------

.PHONY: test-headscale-service
test-headscale-service: ensure-run-as-root
	@$(run_as_root) systemctl is-active --quiet headscale \
		&& echo "[verify] ✅ Service active" \
		|| (echo "[verify] ❌ Service NOT active"; exit 1)

.PHONY: test-headscale-config
test-headscale-config: ensure-run-as-root
	@$(run_as_root) headscale configtest --config /etc/headscale/config.yaml >/dev/null \
		&& echo "[verify] ✅ Configtest passed" \
		|| (echo "[verify] ❌ Configtest FAILED"; exit 1)

.PHONY: test-headscale-acl
test-headscale-acl: ensure-run-as-root
	@$(run_as_root) headscale policy show >/dev/null \
		&& echo "[verify] ✅ ACL policy loaded" \
		|| (echo "[verify] ❌ ACL policy NOT loaded"; exit 1)

.PHONY: test-headscale-nodes
test-headscale-nodes: ensure-run-as-root
	@$(run_as_root) headscale nodes list >/dev/null \
		&& echo "[verify] ✅ Nodes reachable" \
		|| (echo "[verify] ❌ Node list FAILED"; exit 1)

.PHONY: test-headscale-unit
test-headscale-unit:
	@cmp -s config/systemd/headscale.service /etc/systemd/system/headscale.service \
		&& echo "[verify] ✅ systemd unit matches repo" \
		|| (echo "[verify] ❌ systemd unit differs from repo"; exit 1)

.PHONY: test-headscale-override
test-headscale-override:
	@cmp -s config/systemd/headscale.service.d/override.conf /etc/systemd/system/headscale.service.d/override.conf \
		&& echo "[verify] ✅ override matches repo" \
		|| (echo "[verify] ❌ override differs from repo"; exit 1)

# --------------------------------------------------------------------
# Parallel verification suite (runs atomic tests concurrently)
# --------------------------------------------------------------------
headscale-verify: \
	test-headscale-service \
	test-headscale-config \
	test-headscale-acl \
	test-headscale-nodes \
	test-headscale-unit \
	test-headscale-override
	@echo "[verify] 🎉 Parallel verification complete"
