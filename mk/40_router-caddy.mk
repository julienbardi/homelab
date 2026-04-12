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

# ------------------------------------------------------------
# Materialize Caddy binary directly on the router
# ------------------------------------------------------------

# Use the official release tarball (works on router)
ROUTER_CADDY_VERSION ?= 2.11.2
ROUTER_CADDY_ARCH    ?= linux_arm64
ROUTER_CADDY_URL     := https://github.com/caddyserver/caddy/releases/download/v$(ROUTER_CADDY_VERSION)/caddy_$(ROUTER_CADDY_VERSION)_$(ROUTER_CADDY_ARCH).tar.gz

.PHONY: router-caddy-bin
router-caddy-bin: | router-ssh-check router-require-arm64
	@echo "⬇️  Fetching Caddy $(ROUTER_CADDY_VERSION) ($(ROUTER_CADDY_ARCH)) on router"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		mkdir -p "$(dir $(ROUTER_CADDY_BIN))"; \
		cd "$(dir $(ROUTER_CADDY_BIN))"; \
		curl -fsSL "$(ROUTER_CADDY_URL)" -o caddy.tar.gz; \
		tar -xzf caddy.tar.gz caddy; \
		chmod 0755 caddy; \
		mv caddy "$(ROUTER_CADDY_BIN)"; \
		rm caddy.tar.gz; \
	'

# ------------------------------------------------------------
# Push and validate Caddyfile
# ------------------------------------------------------------

.PHONY: router-caddy-config
router-caddy-config: router-firewall-started | router-require-arm64 router-ssh-check
	@echo "📦 Installing Caddyfile on router"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		mkdir -p "$(dir $(ROUTER_CADDYFILE_DST))"; \
	'
	@set -e; \
	EC=0; \
	$(INSTALL_PATH)/install_file_if_changed_v2.sh \
		"" "" \
		"$(ROUTER_CADDYFILE_SRC)" \
		"$(ROUTER_HOST)" "$(ROUTER_SSH_PORT)" \
		"$(ROUTER_CADDYFILE_DST)" \
		"0" "0" "0644" \
		|| EC=$$?; \
	if [ "$$EC" != "0" ] && [ "$$EC" != "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
		exit "$$EC"; \
	fi
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'$(ROUTER_CADDY_BIN) validate --config $(ROUTER_CADDYFILE_DST)'
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '/jffs/scripts/caddy-reload.sh'


# ------------------------------------------------------------
# High-level deploy
# ------------------------------------------------------------

.PHONY: router-caddy
router-caddy: \
	router-caddy-bin \
	router-install-scripts \
	router-firewall-install \
	router-install-ca \
	router-ddns-check \
	router-certs-prepare \
	router-certs-install-caddy \
	router-caddy-config \
	router-caddy-enable

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

# ------------------------------------------------------------
# Health, version, and restart
# ------------------------------------------------------------

.PHONY: router-caddy-version
router-caddy-version: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		if [ -x "$(ROUTER_CADDY_BIN)" ]; then \
			"$(ROUTER_CADDY_BIN)" version; \
		else \
			echo "❌ Caddy binary not found at $(ROUTER_CADDY_BIN)"; \
			exit 1; \
		fi \
	'

.PHONY: router-caddy-health
router-caddy-health: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		if pidof caddy >/dev/null; then \
			echo "✅ Caddy running"; \
		else \
			echo "❌ Caddy not running"; \
			exit 1; \
		fi \
	'

.PHONY: router-caddy-restart
router-caddy-restart: | router-ssh-check
	@echo "🔄 Restarting Caddy on router"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		if pidof caddy >/dev/null; then \
			"$(ROUTER_CADDY_BIN)" stop || true; \
		fi; \
		"$(ROUTER_CADDY_BIN)" start \
	'

# ------------------------------------------------------------
# Install TLS certs for Caddy (from router cert store)
# ------------------------------------------------------------

.PHONY: router-certs-install-caddy
router-certs-install-caddy: | router-ssh-check router-require-run-as-root
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		mkdir -p /jffs/ssl/caddy; \
		cp /jffs/ssl/fullchain.pem /jffs/ssl/caddy/fullchain.pem.tmp; \
		chmod 0644 /jffs/ssl/caddy/fullchain.pem.tmp; \
		mv /jffs/ssl/caddy/fullchain.pem.tmp /jffs/ssl/caddy/fullchain.pem; \
		cp /jffs/ssl/privkey.pem /jffs/ssl/caddy/privkey.pem.tmp; \
		chmod 0600 /jffs/ssl/caddy/privkey.pem.tmp; \
		mv /jffs/ssl/caddy/privkey.pem.tmp /jffs/ssl/caddy/privkey.pem; \
	'

.PHONY: router-caddy-upgrade
router-caddy-upgrade: | router-ssh-check router-require-arm64
	@echo "⬆️  Upgrading Caddy on router"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		mkdir -p $(dir $(ROUTER_CADDY_BIN)); \
		curl -fsSL "$(ROUTER_CADDY_URL)" -o "$(ROUTER_CADDY_BIN).tmp"; \
		chmod 0755 "$(ROUTER_CADDY_BIN).tmp"; \
		mv "$(ROUTER_CADDY_BIN).tmp" "$(ROUTER_CADDY_BIN)"; \
		file "$(ROUTER_CADDY_BIN)" | grep -q "ARM aarch64" \
			|| { echo "❌ Invalid Caddy binary"; exit 1; } \
	'
	@echo "🔄 Restarting Caddy after upgrade"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		if pidof caddy >/dev/null; then \
			"$(ROUTER_CADDY_BIN)" stop || true; \
		fi; \
		"$(ROUTER_CADDY_BIN)" start \
	'

.PHONY: router-caddy-check
router-caddy-check: | router-ssh-check router-require-arm64
	@echo "🔍 Checking Caddy binary"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		if [ ! -x "$(ROUTER_CADDY_BIN)" ]; then \
			echo "❌ Caddy binary missing or not executable"; exit 1; \
		fi \
	'
	@echo "🔍 Checking Caddy version"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '$(ROUTER_CADDY_BIN) version || exit 1'
	@echo "🔍 Checking Caddy process"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		if pidof caddy >/dev/null; then \
			echo "✅ Caddy running"; \
		else \
			echo "❌ Caddy not running"; exit 1; \
		fi \
	'
	@echo "🔍 Validating Caddyfile"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'$(ROUTER_CADDY_BIN) validate --config $(ROUTER_CADDYFILE_DST)'
	@echo "🔍 Reloading Caddy"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '/jffs/scripts/caddy-reload.sh'
	@echo "✅ Caddy check complete"

.PHONY: router-caddy-enable
router-caddy-enable: | router-ssh-check router-require-run-as-root
	@echo "⚙️  Enabling Caddy autostart on router"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		mkdir -p /jffs/scripts; \
		touch /jffs/scripts/services-start; \
		chmod 0755 /jffs/scripts/services-start; \
		if ! grep -q "$(ROUTER_SCRIPTS)/caddy start" /jffs/scripts/services-start; then \
			echo "$(ROUTER_SCRIPTS)/caddy start" >> /jffs/scripts/services-start; \
		fi \
	'
	@echo "✅ Caddy autostart enabled"
