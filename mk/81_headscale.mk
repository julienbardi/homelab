# --------------------------------------------------------------------
# mk/81_headscale.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Uses $(run_as_root) from mk/01_common.mk.
# - Calls with argv tokens, not quoted strings.
# - Operators escaped so they survive Make parsing.
# - Zero-overhead fast-path: Services ONLY recycle on concrete drift.
# --------------------------------------------------------------------

HEADSCALE_BIN := $(INSTALL_PATH)/headscale
HEADSCALE_URL := https://github.com/juanfont/headscale/releases/download/v0.28.0-beta.1/headscale_0.28.0-beta.1_linux_amd64
HEADSCALE_SHA256 := f9ba05660cfbba72a1f6a51f8792c83b5cdabb335ec84b975468ddc8df95f56e

HEADSCALE_STAMP := $(STAMP_DIR)/headscale.installed

HEADSCALE_CONFIG_SRC := config/headscale/config.yaml
HEADSCALE_CONFIG_DST := /etc/headscale/config.yaml

HEADSCALE_DERP_CONFIG_SRC := config/headscale/derp.yaml
HEADSCALE_DERP_CONFIG_DST := /etc/headscale/derp.yaml

HEADSCALE_METRICS_ADDR := $(NAS_LAN_IP):9091
HEADSCALE_METRICS_URL := http://$(HEADSCALE_METRICS_ADDR)/metrics
HEADSCALE_HEALTH_URL := http://127.0.0.1:8910/health

HEADSCALE_CACHE := $(REPO_ROOT).cache/headscale_0.28.0-beta.1_$(shell uname -m)

# Fast-Path Shadow Targets & Change Flags
HEADSCALE_CHANGED_STAMP := $(STAMP_DIR)/headscale_state_changed.stamp
HEADSCALE_CONFIG_SHADOW  := $(STAMP_DIR)/headscale_config.shadow
HEADSCALE_DERP_SHADOW    := $(STAMP_DIR)/headscale_derp.shadow
HEADSCALE_UNIT_SHADOW    := $(STAMP_DIR)/headscale_unit.shadow
HEADSCALE_OVERRIDE_SHADOW:= $(STAMP_DIR)/headscale_override.shadow

.NOTPARALLEL: headscale headscale-restart headscale-verify

.PHONY: \
    headscale \
    headscale-bin \
    headscale-bootstrap \
    headscale-runtime \
    headscale-restart \
    headscale-verify \
    headscale-wait-ready \
    headscale-metrics \
    headscale-logs \
    test-headscale-core \
    test-headscale-unit \
    test-headscale-override \
    rotate-noise-key-dangerous \
    rotate-noise-key

# --------------------------------------------------------------------
# Main Orchestration Target (Gated Fast-Path Entrypoint)
# --------------------------------------------------------------------
headscale: \
    headscale-bin \
    $(HEADSCALE_UNIT_SHADOW) \
    $(HEADSCALE_OVERRIDE_SHADOW) \
    $(HEADSCALE_CONFIG_SHADOW) \
    $(HEADSCALE_DERP_SHADOW) \
    deploy-headscale \
    headscale-restart \
    headscale-acls \
    headscale-verify
	@$(run_as_root) systemctl status headscale --no-pager --lines=0
	@echo "ℹ️  For detailed Headscale status:"
	@echo "      sudo systemctl status headscale"
	@echo "      sudo journalctl -u headscale -n 200"
	@echo "📊 Metrics available at: $(HEADSCALE_METRICS_URL)"
	@echo "🚀 Headscale control plane ready"

# --------------------------------------------------------------------
# Headscale binary (via centralized GitHub installer)
# --------------------------------------------------------------------
headscale-bin: ensure-run-as-root ensure-stamp-dir install-all
	@echo "📦 Ensuring Headscale binary"
	@$(run_as_root) $(INSTALL_PATH)/install_github_asset.sh \
			$(HEADSCALE_URL) \
			$(HEADSCALE_BIN) \
			$(HEADSCALE_SHA256) \
			$(HEADSCALE_STAMP)

# --------------------------------------------------------------------
# Shadow Target Rules (Detects absolute drift securely)
# --------------------------------------------------------------------
$(HEADSCALE_UNIT_SHADOW): config/systemd/headscale.service | headscale-bin
	@OLD_HASH=$$(sha256sum "/etc/systemd/system/headscale.service" 2>/dev/null | awk '{print $$1}') || OLD_HASH=""; \
	NEW_HASH=$$(sha256sum "config/systemd/headscale.service" 2>/dev/null | awk '{print $$1}') || NEW_HASH=""; \
	if [ "$$OLD_HASH" != "$$NEW_HASH" ]; then \
		echo "⚙️ Syncing Headscale systemd unit"; \
		$(run_as_root) install -m 0644 config/systemd/headscale.service /etc/systemd/system/headscale.service; \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) systemctl enable headscale; \
		touch "$(HEADSCALE_CHANGED_STAMP)"; \
	  fi
	@touch "$@"

$(HEADSCALE_OVERRIDE_SHADOW): config/systemd/headscale.service.d/override.conf | headscale-bin
	@OLD_HASH=$$(sha256sum "/etc/systemd/system/headscale.service.d/override.conf" 2>/dev/null | awk '{print $$1}') || OLD_HASH=""; \
	NEW_HASH=$$(sha256sum "config/systemd/headscale.service.d/override.conf" 2>/dev/null | awk '{print $$1}') || NEW_HASH=""; \
	if [ "$$OLD_HASH" != "$$NEW_HASH" ]; then \
		echo "⚙️ Syncing Headscale systemd drop-in override"; \
		$(run_as_root) install -d -m 0755 /etc/systemd/system/headscale.service.d; \
		$(run_as_root) install -m 0644 config/systemd/headscale.service.d/override.conf /etc/systemd/system/headscale.service.d/override.conf; \
		$(run_as_root) systemctl daemon-reload; \
		touch "$(HEADSCALE_CHANGED_STAMP)"; \
	  fi
	@touch "$@"

$(HEADSCALE_CONFIG_SHADOW): $(HEADSCALE_CONFIG_SRC) | headscale-bin
	@OLD_HASH=$$(sha256sum "$(HEADSCALE_CONFIG_DST)" 2>/dev/null | awk '{print $$1}') || OLD_HASH=""; \
	NEW_HASH=$$(sha256sum "$(HEADSCALE_CONFIG_SRC)" 2>/dev/null | awk '{print $$1}') || NEW_HASH=""; \
	if [ "$$OLD_HASH" != "$$NEW_HASH" ]; then \
		echo "🔧 Syncing Headscale system configuration"; \
		$(call install_file,$(HEADSCALE_CONFIG_SRC),$(HEADSCALE_CONFIG_DST),headscale,headscale,0640); \
		touch "$(HEADSCALE_CHANGED_STAMP)"; \
	  fi
	@touch "$@"

$(HEADSCALE_DERP_SHADOW): $(HEADSCALE_DERP_CONFIG_SRC) | headscale-bin
	@OLD_HASH=$$(sha256sum "$(HEADSCALE_DERP_CONFIG_DST)" 2>/dev/null | awk '{print $$1}') || OLD_HASH=""; \
	NEW_HASH=$$(sha256sum "$(HEADSCALE_DERP_CONFIG_SRC)" 2>/dev/null | awk '{print $$1}') || NEW_HASH=""; \
	if [ "$$OLD_HASH" != "$$NEW_HASH" ]; then \
		echo "🔧 Syncing Headscale DERP configuration"; \
		$(call install_file,$(HEADSCALE_DERP_CONFIG_SRC),$(HEADSCALE_DERP_CONFIG_DST),headscale,headscale,0640); \
		touch "$(HEADSCALE_CHANGED_STAMP)"; \
	  fi
	@touch "$@"

# --------------------------------------------------------------------
# Service Lifecycle Control (Strictly Conditional)
# --------------------------------------------------------------------
headscale-restart: ensure-run-as-root
	@NEED_RESTART=0; \
	if [ -f "$(HEADSCALE_CHANGED_STAMP)" ]; then NEED_RESTART=1; fi; \
	if ! $(run_as_root) systemctl is-active --quiet headscale 2>/dev/null; then NEED_RESTART=1; fi; \
	if [ "$$NEED_RESTART" -eq 1 ]; then \
		echo "🔄 Invariant modification verified — restarting Headscale control plane"; \
		$(run_as_root) systemctl restart headscale; \
		rm -f "$(HEADSCALE_CHANGED_STAMP)"; \
	  fi

# --------------------------------------------------------------------
# Verification Suite (Runs read-only checks)
# --------------------------------------------------------------------
headscale-verify: \
    headscale-wait-ready \
    test-headscale-core \
    test-headscale-unit \
    test-headscale-override
	@echo "[verify] 🎉 Parallel verification complete"

headscale-wait-ready: ensure-run-as-root
	@if [ -f "$(HEADSCALE_CHANGED_STAMP)" ] || ! $(run_as_root) systemctl is-active --quiet headscale 2>/dev/null; then \
		echo "ℹ️ Waiting for Headscale API"; \
		$(run_as_root) sh -c '\
			for i in 1 2 3 4 5 6 7 8 9 10; do \
				if curl -fsS "$(HEADSCALE_HEALTH_URL)" >/dev/null 2>&1; then \
					echo "✅ Headscale API ready"; \
					exit 0; \
				fi; \
				sleep 1; \
			done; \
			echo "❌ Headscale API did not become ready"; \
			exit 1; \
		'; \
	  fi

test-headscale-core: ensure-run-as-root
	@$(run_as_root) systemctl is-active --quiet headscale \
		&& echo "[verify] ✅ Service active" \
		|| (echo "[verify] ❌ Service NOT active"; exit 1)
	@$(run_as_root) headscale configtest --config /etc/headscale/config.yaml >/dev/null \
		&& echo "[verify] ✅ Configtest passed" \
		|| (echo "[verify] ❌ Configtest FAILED"; exit 1)
	@$(run_as_root) headscale policy show >/dev/null \
		&& echo "[verify] ✅ ACL policy loaded" \
		|| (echo "[verify] ❌ ACL policy NOT loaded"; exit 1)
	@$(run_as_root) headscale nodes list >/dev/null \
		&& echo "[verify] ✅ Nodes reachable" \
		|| (echo "[verify] ❌ Node list FAILED"; exit 1)

test-headscale-unit:
	@cmp -s config/systemd/headscale.service /etc/systemd/system/headscale.service \
		&& echo "[verify] ✅ systemd unit matches repo" \
		|| (echo "[verify] ❌ systemd unit differs from repo"; exit 1)

test-headscale-override:
	@cmp -s config/systemd/headscale.service.d/override.conf /etc/systemd/system/headscale.service.d/override.conf \
		&& echo "[verify] ✅ override matches repo" \
		|| (echo "[verify] ❌ override differs from repo"; exit 1)

# --------------------------------------------------------------------
# Diagnostics and Administrative Helpers
# --------------------------------------------------------------------
headscale-logs: ensure-run-as-root
	@echo "📜 Tailing Headscale logs (Ctrl-C to exit)"
	@$(run_as_root) journalctl -u headscale -f -n 100

headscale-metrics:
	@echo "📊 Headscale metrics:"
	@curl -fsS $(HEADSCALE_METRICS_URL) | sed -n '1,40p'

rotate-noise-key-dangerous: rotate-noise-key

rotate-noise-key: ensure-run-as-root headscale-bin
	@echo "🔥 ROTATE HEADSCALE NOISE KEY — this will disconnect all clients"
	@read -p "Type YES to ROTATE THE NOISE KEY: " confirm && [ "$$confirm" = "YES" ] || (echo "aborting"; exit 1)
	@echo "⚠️ Proceeding with Noise key rotation — clients must re-authenticate"
	@$(run_as_root) systemctl stop headscale
	@$(run_as_root) rm -f /etc/headscale/noise_private.key
	@$(run_as_root) bash -c "umask 077; $(HEADSCALE_BIN) generate private-key > /etc/headscale/noise_private.key && chown headscale:headscale /etc/headscale/noise_private.key && chmod 600 /etc/headscale/noise_private.key"
	@$(run_as_root) systemctl start headscale
	@echo "🔄 Noise private key rotated and Headscale restarted"
	@echo "🔍 Validating Headscale service"
	@$(run_as_root) bash -c "systemctl is-active --quiet headscale && echo '✅ Headscale service is running' || (echo '✘ Headscale service not active'; exit 1)"
	@$(run_as_root) bash -c "headscale version >/dev/null && echo '✅ Headscale CLI responsive' || (echo '✘ Headscale CLI failed to connect'; exit 1)"

# Deprecated backward compatibility targets
headscale-bootstrap: headscale-bin
headscale-runtime:
headscale-prereqs: