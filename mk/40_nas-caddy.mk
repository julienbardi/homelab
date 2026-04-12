# 40_nas-caddy.mk
NAS_CADDY_BIN    := /usr/bin/caddy
NAS_CADDY_BACKUP := /usr/bin/caddy.orig
NAS_STAMP_CADDY  := $(STAMP_DIR)/caddy.installed

NAS_CADDYFILE     := /etc/caddy/Caddyfile
SRC_NAS_CADDYFILE := $(REPO_ROOT)config/caddy/Caddyfile

# Define the Admin API address to bypass UGOS loopback issues
NAS_CADDY_ADMIN_ADDR := 10.89.12.4:2019

.PHONY: nas-caddy
nas-caddy: ensure-run-as-root gitcheck nas-assert-caddy-ports-free deploy-caddy
	@set -euo pipefail; \
	echo "🔐 Securing certificate permissions"; \
	$(run_as_root) chown -R root:caddy /etc/ssl/caddy; \
	$(run_as_root) chmod 750 /etc/ssl/caddy; \
	$(run_as_root) chmod 640 /etc/ssl/caddy/bardi.ch.cer /etc/ssl/caddy/bardi.ch.key; \
	echo "📄⬇️ Installing Caddyfile"; \
	$(run_as_root) install -d -m 0755 -o root -g root /etc/caddy; \
	changed=0; \
	rc=0; \
	$(call install_file,$(SRC_NAS_CADDYFILE),$(NAS_CADDYFILE),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	echo "📦 Deploying custom Caddy binary with rate_limit plugin"; \
	#if [ -x "$(NAS_CADDY_BIN)" ] && [ ! -f "$(NAS_CADDY_BACKUP)" ]; then \
	#    $(run_as_root) mv "$(NAS_CADDY_BIN)" "$(NAS_CADDY_BACKUP)"; \
	#    echo "💾 Original Caddy backed up -> $(NAS_CADDY_BACKUP)"; \
	#fi; \
	#$(run_as_root) install -m 0755 -o root -g root /tmp/caddy "$(NAS_CADDY_BIN)"; \
	echo "🔎 Verifying installed Caddy"; \
	if ! "$(NAS_CADDY_BIN)" version >/dev/null 2>&1; then \
		echo "❌ Installed Caddy not executable"; \
		[ -f "$(NAS_CADDY_BACKUP)" ] && $(run_as_root) mv "$(NAS_CADDY_BACKUP)" "$(NAS_CADDY_BIN)"; \
		exit 1; \
	fi; \
	if ! "$(NAS_CADDY_BIN)" list-modules | grep -q '^http.handlers.rate_limit$$'; then \
		echo "❌ rate_limit plugin not found in installed binary"; \
		[ -f "$(NAS_CADDY_BACKUP)" ] && $(run_as_root) mv "$(NAS_CADDY_BACKUP)" "$(NAS_CADDY_BIN)"; \
		exit 1; \
	fi; \
	VERSION=$$("$(NAS_CADDY_BIN)" version); \
	echo "✔ Caddy verified with rate_limit plugin: $$VERSION"; \
	echo "version=$$VERSION installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee "$(NAS_STAMP_CADDY)" >/dev/null; \
	\
	echo "🚀 Applying Caddy service"; \
	$(run_as_root) systemctl enable caddy; \
	if $(run_as_root) systemctl is-active --quiet caddy; then \
		if [ "$$changed" -eq 1 ]; then \
			if ! $(run_as_root) "$(NAS_CADDY_BIN)" reload --config "$(NAS_CADDYFILE)" --address "$(NAS_CADDY_ADMIN_ADDR)"; then \
				echo "⚠️ Reload failed (likely Admin API change). Restarting service..."; \
				$(run_as_root) systemctl restart caddy && echo "✅ Restarted successfully"; \
			else \
				echo "✅ Reloaded via $(NAS_CADDY_ADMIN_ADDR) (config changed)"; \
			fi; \
		else \
			echo "ℹ️ Caddyfile unchanged — no reload needed"; \
		fi; \
	else \
		$(run_as_root) systemctl restart caddy && echo "✅ Started/Restarted successfully"; \
	fi

.PHONY: nas-caddy-validate nas-caddy-fmt

.PHONY: nas-caddy-validate nas-caddy-fmt

nas-caddy-validate:
	@if ! sudo [ -f /etc/ssl/caddy/bardi.ch.cer ]; then \
	  echo "⚠️ Certs missing (/etc/ssl/caddy/bardi.ch.cer); skipping full validation"; \
	  echo "👉 Run 'make deploy-caddy' or 'make caddy' once to install certs."; \
	  exit 0; \
	fi
	@echo "🔎 Validating Caddyfile"
	@sudo "$(NAS_CADDY_BIN)" validate --config "$(SRC_NAS_CADDYFILE)"

nas-caddy-fmt:
	@echo "🧹 Formatting Caddyfile"
	@sudo "$(NAS_CADDY_BIN)" fmt --overwrite "$(SRC_NAS_CADDYFILE)"

.PHONY: nas-assert-caddy-ports-free
nas-assert-caddy-ports-free: ensure-run-as-root
	@conflict=$$($(run_as_root) ss -H -tlnp '( sport = :80 or sport = :443 )' | grep -v caddy || true); \
	if [ -n "$$conflict" ]; then \
		echo "❌ ERROR: Port 80 or 443 is already in use:"; \
		echo "$$conflict"; \
		echo ""; \
		echo "👉 UGOS nginx is likely still redirecting these ports."; \
		echo ""; \
		echo "Please go to:"; \
		echo "  Control Panel -> Device Connection -> Portal Settings"; \
		echo ""; \
		echo "Then DISABLE:"; \
		echo "  ☐ Redirect port 80 to HTTP port"; \
		echo "  ☐ Redirect port 443 to HTTPS port"; \
		echo ""; \
		echo "Apply the settings, then re-run:"; \
		echo "  make caddy"; \
		echo ""; \
		exit 1; \
	fi