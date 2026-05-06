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

export ROUTER_CADDY_BIN

one_line = $(subst $(newline), ,$(1))
newline := $(shell printf "\n")

# ------------------------------------------------------------
# Architecture requirement
# ------------------------------------------------------------

.PHONY: router-require-arm64
router-require-arm64: | router-ssh-check
	@$(call WITH_SECRETS, \
		ssh $(SSH_OPTS) -p "$$router_ssh_port" "$$router_user@$$router_addr" uname -m | grep -q aarch64 \
	)

# ------------------------------------------------------------
# Install / upgrade Caddy binary (content-addressed)
# ------------------------------------------------------------

ROUTER_CADDY_BIN_CMD := \
  set -e; \
  mkdir -p '$(dir $(ROUTER_CADDY_BIN))'; \
  mkdir -p '$(dir $(ROUTER_CADDY_STAMP))'; \
  if cat '$(ROUTER_CADDY_STAMP)' 2>/dev/null | grep -qx '$(ROUTER_CADDY_SHA256)' && \
	 [ -x '$(ROUTER_CADDY_BIN)' ]; then \
	  echo "⏩ caddy $(ROUTER_CADDY_VERSION) fast-path OK"; \
	  exit 0; \
  fi; \
  echo "⬇️  Downloading Caddy tarball"; \
  cd '$(dir $(ROUTER_CADDY_BIN))'; \
  curl -fsSL '$(ROUTER_CADDY_URL)' -o caddy.tar.gz; \
  echo '$(ROUTER_CADDY_SHA256)  caddy.tar.gz' | sha256sum -c - >/dev/null; \
  tar -xzf caddy.tar.gz caddy; \
  chmod 0755 caddy; \
  mv caddy '$(ROUTER_CADDY_BIN)'; \
  echo '$(ROUTER_CADDY_SHA256)' > '$(ROUTER_CADDY_STAMP)'; \
  rm -f caddy.tar.gz; \
  echo "✅ Installed Caddy $(ROUTER_CADDY_VERSION)"

.PHONY: router-caddy-bin
router-caddy-bin: | router-ssh-check router-require-arm64
	@echo "⬇️  Ensuring Caddy $(ROUTER_CADDY_VERSION) ($(ROUTER_CADDY_ARCH)) on router"
	@$(call WITH_SECRETS, \
		ssh "$$router_user@$$router_addr" -p "$$router_ssh_port" "$(call one_line,$(ROUTER_CADDY_BIN_CMD))" \
	)

# ------------------------------------------------------------
# Install TLS certs for Caddy
# ------------------------------------------------------------

.PHONY: router-certs-install-caddy
router-certs-install-caddy: | router-ssh-check router-require-run-as-root
	@$(call WITH_SECRETS, \
		ssh -p "$$router_ssh_port" "$$router_user@$$router_addr" '\
			set -e; \
			mkdir -p /jffs/ssl/caddy; \
			cp /jffs/ssl/fullchain.pem /jffs/ssl/caddy/fullchain.pem.tmp; \
			chmod 0644 /jffs/ssl/caddy/fullchain.pem.tmp; \
			mv /jffs/ssl/caddy/fullchain.pem.tmp /jffs/ssl/caddy/fullchain.pem; \
			cp /jffs/ssl/privkey.pem /jffs/ssl/caddy/privkey.pem.tmp; \
			chmod 0600 /jffs/ssl/caddy/privkey.pem.tmp; \
			mv /jffs/ssl/caddy/privkey.pem.tmp /jffs/ssl/caddy/privkey.pem; \
		' \
	)

# ------------------------------------------------------------
# Push and validate Caddyfile
# ------------------------------------------------------------

.PHONY: router-caddy-config
router-caddy-config: router-certs-install-caddy | router-require-arm64 router-ssh-check
	@echo "📦 Installing Caddyfile on router"

	# Install file (local logic)
	@set -e; \
	if [ -z "$(INSTALL_FILE_IF_CHANGED)" ]; then \
		echo "❌ INSTALL_FILE_IF_CHANGED is empty"; exit 1; \
	fi; \
	EC=0; \
	$(INSTALL_FILE_IF_CHANGED) \
		"" "" \
		"$(ROUTER_CADDYFILE_SRC)" \
		"$$router_user@$$router_addr" "$$router_ssh_port" \
		"$(ROUTER_CADDYFILE_DST)" \
		"0" "0" "0644" \
		|| EC=$$?; \
	if [ "$$EC" != "0" ] && [ "$$EC" != "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then exit "$$EC"; fi

	# Validate + reload in one SSH session
	@$(call WITH_SECRETS, \
		ssh -p "$$router_ssh_port" "$$router_user@$$router_addr" '\
			set -e; \
			echo "🔍 Validating Caddyfile"; \
			"$(ROUTER_CADDY_BIN)" validate --config "$(ROUTER_CADDYFILE_DST)" --adapter caddyfile; \
			echo "🔄 Reloading Caddy"; \
			/jffs/scripts/caddy-reload.sh; \
		' \
	)

# ------------------------------------------------------------
# High-level deploy
# ------------------------------------------------------------

.PHONY: router-caddy
router-caddy: \
	router-caddy-bin \
	router-install-scripts \
	router-firewall-install \
	router-ddns \
	router-certs-prepare \
	router-certs-install-caddy \
	router-caddy-config \
	router-caddy-enable

# ------------------------------------------------------------
# Version
# ------------------------------------------------------------

.PHONY: router-caddy-version
router-caddy-version: | router-ssh-check
	@$(call WITH_SECRETS, \
		ssh -p "$$router_ssh_port" "$$router_user@$$router_addr" '"$(ROUTER_CADDY_BIN)" version' \
	)

# ------------------------------------------------------------
# Health
# ------------------------------------------------------------

.PHONY: router-caddy-health
router-caddy-health: | router-ssh-check
	@$(call WITH_SECRETS, \
		ssh -p "$$router_ssh_port" "$$router_user@$$router_addr" '\
			if pidof caddy >/dev/null; then \
				echo "✅ Caddy running"; \
			else \
				echo "❌ Caddy not running"; exit 1; \
			fi \
		' \
	)

# ------------------------------------------------------------
# Restart
# ------------------------------------------------------------

.PHONY: router-caddy-restart
router-caddy-restart: | router-ssh-check
	@echo "🔄 Restarting Caddy on router"
	@$(call WITH_SECRETS, \
		ssh -p "$$router_ssh_port" "$$router_user@$$router_addr" '/jffs/scripts/caddy-reload.sh' \
	)

# ------------------------------------------------------------
# Full health check
# ------------------------------------------------------------

.PHONY: router-caddy-check
router-caddy-check: | router-ssh-check router-require-arm64
	@echo "🔍 Checking Caddy on router"
	@$(call WITH_SECRETS, \
		ssh -p "$$router_ssh_port" "$$router_user@$$router_addr" '\
			set -e; \
			echo "🔍 Checking Caddy binary"; \
			[ -x "$(ROUTER_CADDY_BIN)" ] || { echo "❌ Missing Caddy binary"; exit 1; }; \
			echo "🔍 Checking Caddy version"; \
			"$(ROUTER_CADDY_BIN)" version; \
			echo "🔍 Checking Caddy process"; \
			pidof caddy >/dev/null && echo "✅ Caddy running" || { echo "❌ Caddy not running"; exit 1; }; \
			echo "🔍 Validating Caddyfile"; \
			"$(ROUTER_CADDY_BIN)" validate --config "$(ROUTER_CADDYFILE_DST)" --adapter caddyfile; \
			echo "🔄 Reloading Caddy"; \
			/jffs/scripts/caddy-reload.sh; \
			echo "✅ Caddy check complete"; \
		' \
	)

# ------------------------------------------------------------
# Autostart
# ------------------------------------------------------------

.PHONY: router-caddy-enable
router-caddy-enable: | router-ssh-check router-require-run-as-root
	@echo "⚙️  Enabling Caddy autostart on router"
	@$(call WITH_SECRETS, \
		ssh -p "$$router_ssh_port" "$$router_user@$$router_addr" '\
			set -e; \
			mkdir -p /jffs/scripts; \
			touch /jffs/scripts/services-start; \
			chmod 0755 /jffs/scripts/services-start; \
			if ! grep -q "/jffs/scripts/caddy-reload.sh" /jffs/scripts/services-start; then \
				echo "/jffs/scripts/caddy-reload.sh" >> /jffs/scripts/services-start; \
			fi; \
		' \
	)
	@echo "✅ Caddy autostart enabled"
