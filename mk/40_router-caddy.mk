# mk/40_router-caddy.mk — Router Caddy lifecycle (namespaced)
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
.PHONY: router-require-arm64
router-require-arm64: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) uname -m | grep -q aarch64

.NOTPARALLEL: router-caddy-install router-caddy-config

# ------------------------------------------------------------
# Install Caddy binary
# ------------------------------------------------------------

.PHONY: router-caddy-install
router-caddy-install: $(ROUTER_CADDY_BIN) | router-ssh-check router-require-arm64
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_CADDY_BIN),$(ROUTER_SCRIPTS)/caddy)

# ------------------------------------------------------------
# Push and validate Caddyfile
# ------------------------------------------------------------

.PHONY: router-caddy-config
router-caddy-config: router-firewall-started | router-require-arm64
	@scp -q -O -P $(ROUTER_SSH_PORT) \
		$(ROUTER_CADDYFILE_SRC) \
		$(ROUTER_HOST):$(ROUTER_CADDYFILE_DST)
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'$(ROUTER_CADDY_BIN) validate --config $(ROUTER_CADDYFILE_DST)'
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '/jffs/scripts/caddy-reload.sh'


# ------------------------------------------------------------
# High‑level deploy
# ------------------------------------------------------------

.PHONY: router-caddy-deploy
router-caddy-deploy: router-certs-prepare router-caddy-install router-caddy-config

# ------------------------------------------------------------
# Router‑side Caddy entrypoint
# ------------------------------------------------------------

.PHONY: router-caddy
router-caddy: router-caddy-deploy

# ------------------------------------------------------------
# Status & control
# ------------------------------------------------------------

.PHONY: router-caddy-status
router-caddy-status: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) pidof caddy || true

.PHONY: router-caddy-start
router-caddy-start: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '$(ROUTER_CADDY_BIN) start'

.PHONY: router-caddy-stop
router-caddy-stop: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '$(ROUTER_CADDY_BIN) stop'
