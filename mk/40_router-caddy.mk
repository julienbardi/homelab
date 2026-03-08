# mk/caddy.mk
# ------------------------------------------------------------
# CADDY LIFECYCLE MANAGEMENT
# ------------------------------------------------------------
#
# Responsibilities:
#   - Install Caddy binary on router
#   - Push and validate Caddyfile
#   - Reload running Caddy process
#   - Provide health and status checks
#
# Non-responsibilities:
#   - Certificate issuance (handled by certs.mk)
#   - Firewall rules (handled by router.mk)
#   - Privilege escalation (handled by run-as-root)
#
# Contracts:
#   - MUST NOT invoke $(MAKE)
#   - MUST be correct under 'make -j'
#   - MUST NOT rely on timestamps for remote state
# ------------------------------------------------------------
.PHONY: require-arm64
require-arm64: | ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) uname -m | grep -q aarch64

.NOTPARALLEL: caddy-install caddy-config

.PHONY: caddy-install
caddy-install: | ssh-check require-arm64
	$(call deploy_if_changed, $(SRC_SCRIPTS)/caddy, $(CADDY_BIN))

.PHONY: caddy-config
caddy-config: firewall-started | require-arm64
	@scp -q -O -P $(ROUTER_SSH_PORT) $(CADDYFILE_SRC) $(ROUTER_HOST):$(CADDYFILE_DST)
	@$(run_as_root) $(CADDY_BIN) validate --config $(CADDYFILE_DST)
	@$(run_as_root) /jffs/scripts/caddy-reload.sh

.PHONY: deploy-caddy
deploy-caddy: router-prepare caddy-install caddy-config

.PHONY: caddy
caddy: deploy-caddy

.PHONY: caddy-status
caddy-status: | ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) pidof caddy || true

.PHONY: caddy-start
caddy-start: | ssh-check
	@$(run_as_root) $(CADDY_BIN) start

.PHONY: caddy-stop
caddy-stop: | ssh-check
	@$(run_as_root) $(CADDY_BIN) stop
