# 40_nas-caddy.mk
NAS_CADDY_BIN               ?= /usr/bin/caddy
NAS_CADDY_BACKUP            ?= /usr/bin/caddy.orig
NAS_STAMP_CADDY             ?= $(STAMP_DIR_ROOT)/caddy.installed

NAS_CADDYFILE               := /etc/caddy/Caddyfile
SRC_NAS_CADDYFILE           := $(REPO_ROOT)/config/caddy/Caddyfile
SRC_NAS_SERVICE             := $(REPO_ROOT)/config/caddy/caddy.service
NAS_SYSTEMD_CADDY           := /etc/systemd/system/caddy.service

# Official Caddy download API endpoint with rate_limit plugin requested
CADDY_DOWNLOAD_URL          ?= https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com%2Fmholt%2Fcaddy-ratelimit

.PHONY: nas-caddy
nas-caddy: gitcheck nas-assert-caddy-ports-free acme-issue deploy-caddy install-all
	@set -euo pipefail; \
	echo "🔐 Preparing Caddy binary backup and system users/groups"; \
	$(run_as_root) bash -c 'set -euo pipefail; \
		if [ -f "$(NAS_CADDY_BIN)" ]; then \
			cp -f "$(NAS_CADDY_BIN)" "$(NAS_CADDY_BACKUP)"; \
			chmod +x "$(NAS_CADDY_BACKUP)"; \
		fi; \
		if ! getent group caddy >/dev/null 2>&1; then \
			groupadd --system caddy; \
		fi; \
		if ! getent passwd caddy >/dev/null 2>&1; then \
			useradd --system --gid caddy --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy; \
		fi; \
		install -d -m 0750 -o root -g caddy /etc/ssl/caddy; \
	'; \
	\
	echo "📥 Installing custom Caddy binary with rate_limit plugin via install_url_file_if_changed"; \
	caddy_rc=0; \
	$(run_as_root) $(INSTALL_URL_FILE_IF_CHANGED) \
		"$(CADDY_DOWNLOAD_URL)" \
		"$(NAS_CADDY_BIN)" \
		root root 0755 "" 86400 || caddy_rc=$$?; \
	case "$$caddy_rc" in \
		$(INSTALL_IF_CHANGED_EXIT_UNCHANGED)|$(INSTALL_IF_CHANGED_EXIT_CHANGED)) ;; \
		*) echo "❌ Failed to download/install Caddy binary"; exit "$$caddy_rc" ;; \
	esac; \
	\
	echo "📋⬇️ Installing SSL Certificates"; \
	$(call install_file,$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).cer,/etc/ssl/caddy/bardi.ch.cer,root,caddy,0640); \
	$(call install_file,$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).key,/etc/ssl/caddy/bardi.ch.key,root,caddy,0640); \
	\
	echo "📋⬇️ Installing Caddyfile"; \
	$(run_as_root) install -d -m 0755 -o $(ROOT_UID) -g $(ROOT_GID) /etc/caddy; \
	changed=0; \
	rc=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
		localhost 22 "$(SRC_NAS_CADDYFILE)" 10.89.12.4 22 "$(NAS_CADDYFILE)" \
		root root 0644 || rc=$$?; \
	case "$$rc" in \
		$(INSTALL_IF_CHANGED_EXIT_UNCHANGED)) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	\
	echo "📋⬇️ Installing Caddy systemd service"; \
	$(call install_file,$(SRC_NAS_SERVICE),$(NAS_SYSTEMD_CADDY),root,root,0644); \
	\
	echo "🔍 Verifying installed Caddy and applying service"; \
	$(run_as_root) bash -c 'set -euo pipefail; \
		CHANGED="$$1"; \
		if ! "$(NAS_CADDY_BIN)" version >/dev/null 2>&1; then \
			echo "❌ Installed Caddy not executable"; \
			[ -f "$(NAS_CADDY_BACKUP)" ] && mv "$(NAS_CADDY_BACKUP)" "$(NAS_CADDY_BIN)"; \
			exit 1; \
		fi; \
		if ! "$(NAS_CADDY_BIN)" list-modules | grep -q "^http.handlers.rate_limit$$"; then \
			echo "❌ rate_limit plugin not found in installed binary"; \
			[ -f "$(NAS_CADDY_BACKUP)" ] && mv "$(NAS_CADDY_BACKUP)" "$(NAS_CADDY_BIN)"; \
			exit 1; \
		fi; \
		VERSION=$$("$(NAS_CADDY_BIN)" version); \
		echo "✅ Caddy verified with rate_limit plugin: $$VERSION"; \
		echo "version=$$VERSION installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			> "$(NAS_STAMP_CADDY)"; \
		\
		systemctl daemon-reload; \
		systemctl enable caddy; \
		if systemctl is-active --quiet caddy; then \
			if [ "$$CHANGED" -eq 1 ]; then \
				if ! "$(NAS_CADDY_BIN)" reload --config "$(NAS_CADDYFILE)"; then \
					echo "⚠️ Reload failed. Restarting service..."; \
					systemctl restart caddy && echo "✅ Restarted successfully"; \
				else \
					echo "✅ Reloaded Caddy successfully (config changed)"; \
				fi; \
			else \
				echo "ℹ️ Caddyfile unchanged — no reload needed"; \
			fi; \
		else \
			systemctl restart caddy && echo "✅ Started/Restarted successfully"; \
		fi \
	' -- "$$changed"

.PHONY: nas-caddy-validate nas-caddy-fmt

nas-caddy-validate:
	@if ! sudo [ -f /etc/ssl/caddy/bardi.ch.cer ]; then \
	  echo "⚠️ Certs missing (/etc/ssl/caddy/bardi.ch.cer); skipping full validation"; \
	  echo "➡️ Run 'make deploy-caddy' or 'make nas-caddy' once to install certs."; \
	  exit 0; \
	fi
	@echo "🔍 Validating Caddyfile"
	@sudo "$(NAS_CADDY_BIN)" validate --config "$(SRC_NAS_CADDYFILE)"

nas-caddy-fmt:
	@echo " Formatting Caddyfile"
	@sudo "$(NAS_CADDY_BIN)" fmt --overwrite "$(SRC_NAS_CADDYFILE)"

.PHONY: free-web-ports
free-web-ports:
	@echo "🛑 Stopping and removing conflicting netbird-traefik proxy..."
	@container_id=$$(docker ps -q --filter "name=netbird-traefik" 2>/dev/null || true); \
	if [ -n "$$container_id" ]; then \
		docker stop $$container_id; \
		docker rm $$container_id; \
		echo "🟢 Conflicting proxy container removed successfully."; \
	else \
		echo "ℹ️ No netbird-traefik container found running."; \
	fi

.PHONY: nas-assert-caddy-ports-free
nas-assert-caddy-ports-free:
	@conflict=$$($(run_as_root) ss -H -tlnp '( sport = :80 or sport = :443 )' | grep -v caddy || true); \
	if [ -n "$$conflict" ]; then \
		echo "❌ ERROR: Port 80 or 443 is already in use:"; \
		echo "$$conflict"; \
		echo ""; \
		echo "➡️ To automatically free ports 80/443 by stopping the conflicting container, run:"; \
		echo "   make free-web-ports nas-caddy"; \
		echo ""; \
		exit 1; \
	fi