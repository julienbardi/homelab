# --------------------------------------------------------------------
# mk/81_headscale.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Uses $(run_as_root) from mk/01_common.mk.
# - Calls with argv tokens, not quoted strings.
# - Operators escaped so they survive Make parsing.
# --------------------------------------------------------------------

HEADSCALE_BIN := $(INSTALL_PATH)/headscale
HEADSCALE_URL := https://github.com/juanfont/headscale/releases/download/v0.28.0-beta.1/headscale_0.28.0-beta.1_linux_amd64

HEADSCALE_CONFIG_SRC := config/headscale/config.yaml
HEADSCALE_CONFIG_DST := /etc/headscale/config.yaml

HEADSCALE_DERP_CONFIG_SRC := config/headscale/derp.yaml
HEADSCALE_DERP_CONFIG_DST := /etc/headscale/derp.yaml

HEADSCALE_METRICS_ADDR := $(NAS_LAN_IP):9091

WAIT_FOR_COMMAND := $(INSTALL_PATH)/wait_for_command.sh

.NOTPARALLEL: headscale headscale-restart headscale-verify

# --------------------------------------------------------------------
# Configuration rendering (idempotent)
# --------------------------------------------------------------------
.PHONY: headscale-config
headscale-config: ensure-run-as-root $(HEADSCALE_CONFIG_SRC)
	@echo "📦 Installing Headscale configuration"
	@$(run_as_root) $(INSTALL_IF_CHANGED) \
	    "$(HEADSCALE_CONFIG_SRC)" \
	    "$(HEADSCALE_CONFIG_DST)" \
	    headscale headscale 0640 || [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

.PHONY: headscale-derp-config
headscale-derp-config: ensure-run-as-root $(HEADSCALE_DERP_CONFIG_SRC)
	@echo "📦 Installing Headscale DERP configuration"
	@$(run_as_root) $(INSTALL_IF_CHANGED) \
	    "$(HEADSCALE_DERP_CONFIG_SRC)" \
	    "$(HEADSCALE_DERP_CONFIG_DST)" \
	    headscale headscale 0640 || [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

# --------------------------------------------------------------------
# Bootstrap (one-time, idempotent)
# --------------------------------------------------------------------
.PHONY: headscale-bin
headscale-bin: ensure-run-as-root
	@echo "📦 Ensuring Headscale binary"
	@$(run_as_root) bash -c '\
	    set -euo pipefail; \
	    tmp=$$(mktemp); \
	    trap "rm -f $$tmp" EXIT; \
	    curl -fsSL "$(HEADSCALE_URL)" -o "$$tmp"; \
	    $(INSTALL_IF_CHANGED) "$$tmp" "$(HEADSCALE_BIN)" root root 0755 || [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
	'

# --------------------------------------------------------------------
# Tail Headscale logs
# --------------------------------------------------------------------
.PHONY: headscale-logs
headscale-logs: ensure-run-as-root
	@echo "📜 Tailing Headscale logs (Ctrl-C to exit)"
	@$(run_as_root) journalctl -u headscale -f -n 100

# --------------------------------------------------------------------
# Headscale provisioning prerequisites (parallel-safe)
# --------------------------------------------------------------------
.PHONY: headscale-bootstrap
headscale-bootstrap: \
	headscale-bin \
	headscale-systemd

.PHONY: headscale-runtime
headscale-runtime: \
	harden-groups \
	headscale-config \
	headscale-derp-config \
	deploy-headscale

.PHONY: headscale-prereqs
headscale-prereqs: \
	headscale-bootstrap \
	headscale-runtime

# --------------------------------------------------------------------
# Runtime orchestration (safe to re-run)
# --------------------------------------------------------------------
.PHONY: headscale
headscale: \
	headscale-prereqs \
	headscale-restart \
	headscale-acls \
	headscale-verify
	@$(run_as_root) systemctl status headscale --no-pager --lines=0
	@echo "ℹ️  For detailed Headscale status:"
	@echo "      sudo systemctl status headscale"
	@echo "      sudo journalctl -u headscale -n 200"
	@echo "📊 Metrics available at: http://$(HEADSCALE_METRICS_ADDR)/metrics"
	@echo "🚀 Headscale control plane ready"

.PHONY: headscale-restart
headscale-restart: ensure-run-as-root
	@echo "🔁 Restarting Headscale"
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl restart headscale

# --------------------------------------------------------------------
# Install Headscale systemd unit (static, declarative)
# --------------------------------------------------------------------
.PHONY: headscale-systemd
headscale-systemd: ensure-run-as-root
	@echo "⚙️ Installing Headscale systemd unit"
	@$(run_as_root) install -m 0644 config/systemd/headscale.service /etc/systemd/system/headscale.service
	@$(run_as_root) install -d -m 0755 /etc/systemd/system/headscale.service.d
	@$(run_as_root) install -m 0644 config/systemd/headscale.service.d/override.conf /etc/systemd/system/headscale.service.d/override.conf
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable headscale

# --------------------------------------------------------------------
# Headscale verification (post-deploy checks)
# --------------------------------------------------------------------


# --------------------------------------------------------------------
# Verification (post-deploy, read-only)
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
# NOTE:
# - Verification targets must never mutate state
# - Safe to run repeatedly
# - Intended for post-deploy validation
headscale-verify: \
	headscale-wait-ready \
	test-headscale-service \
	test-headscale-config \
	test-headscale-acl \
	test-headscale-nodes \
	test-headscale-unit \
	test-headscale-override
	@echo "[verify] 🎉 Parallel verification complete"

.PHONY: headscale-wait-ready
headscale-wait-ready: ensure-run-as-root install-all
	@echo "⏳ Waiting for Headscale API"
	@$(run_as_root) $(WAIT_FOR_COMMAND) curl -fsS http://127.0.0.1:8910/health
	@echo "✅ Headscale API ready"

.PHONY: headscale-metrics
headscale-metrics:
	@echo "📊 Headscale metrics:"
	@curl -fsS http://$(HEADSCALE_METRICS_ADDR)/metrics | sed -n '1,40p'

# --------------------------------------------------------------------
# � ️  Destructive operations (operator-only)
# --------------------------------------------------------------------
# WARNING:
# - Invalidates Headscale identity
# - Disconnects all clients
# - Requires client re-authentication
# - Must never be run casually
# POLICY:
# - Noise keys define Headscale identity
# - Rotation is equivalent to identity reset
# - Must be coordinated with clients
.PHONY: rotate-noise-key-dangerous
rotate-noise-key-dangerous: rotate-noise-key

.PHONY: rotate-noise-key
rotate-noise-key: ensure-run-as-root headscale-bin headscale-systemd
	@echo "🔥 ROTATE HEADSCALE NOISE KEY — this will disconnect all clients"
	@read -p "Type YES to ROTATE THE NOISE KEY: " confirm && [ "$$confirm" = "YES" ] || (echo "aborting"; exit 1)
	@echo "� ️  Proceeding with Noise key rotation — clients must re-authenticate"
	@$(run_as_root) systemctl stop headscale
	@$(run_as_root) rm -f /etc/headscale/noise_private.key
	@$(run_as_root) bash -c "umask 077; $(HEADSCALE_BIN) generate private-key > /etc/headscale/noise_private.key && chown headscale:headscale /etc/headscale/noise_private.key && chmod 600 /etc/headscale/noise_private.key"
	@$(run_as_root) systemctl start headscale
	@echo "🔄 Noise private key rotated and Headscale restarted"
	@echo "🔍 Validating Headscale service"
	@$(run_as_root) bash -c "systemctl is-active --quiet headscale && echo '✅ Headscale service is running' || (echo '✘ Headscale service not active'; exit 1)"
	@$(run_as_root) bash -c "headscale version >/dev/null && echo '✅ Headscale CLI responsive' || (echo '✘ Headscale CLI failed to connect'; exit 1)"
