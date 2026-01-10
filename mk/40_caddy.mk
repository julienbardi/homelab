# mk/40_caddy.mk

CADDY_BIN    := /usr/bin/caddy
CADDY_BACKUP := /usr/bin/caddy.orig
STAMP_CADDY  := $(STAMP_DIR)/caddy.installed

CADDYFILE    := /etc/caddy/Caddyfile
SRC_CADDYFILE:= $(HOMELAB_DIR)/config/caddy/Caddyfile

.PHONY: caddy
caddy: ensure-run-as-root gitcheck assert-caddy-ports-free
	@set -euo pipefail; \
	echo "📄⬇️ Installing Caddyfile"; \
	$(run_as_root) install -d -m 0755 -o root -g root /etc/caddy; \
	$(run_as_root) install -m 0644 -o root -g root "$(SRC_CADDYFILE)" "$(CADDYFILE)"; \
	echo "📦 Deploying custom Caddy binary with rate_limit plugin"; \
	#if [ -x "$(CADDY_BIN)" ] && [ ! -f "$(CADDY_BACKUP)" ]; then \
	#	$(run_as_root) mv "$(CADDY_BIN)" "$(CADDY_BACKUP)"; \
	#	echo "💾 Original Caddy backed up → $(CADDY_BACKUP)"; \
	#fi; \
	#$(run_as_root) install -m 0755 -o root -g root /tmp/caddy "$(CADDY_BIN)"; \
	echo "🔎 Verifying installed Caddy"; \
	if ! "$(CADDY_BIN)" version >/dev/null 2>&1; then \
		echo "❌ Installed Caddy not executable"; \
		[ -f "$(CADDY_BACKUP)" ] && $(run_as_root) mv "$(CADDY_BACKUP)" "$(CADDY_BIN)"; \
		exit 1; \
	fi; \
	if ! "$(CADDY_BIN)" list-modules | grep -q '^http.handlers.rate_limit$$'; then \
		echo "❌ rate_limit plugin not found in installed binary"; \
		[ -f "$(CADDY_BACKUP)" ] && $(run_as_root) mv "$(CADDY_BACKUP)" "$(CADDY_BIN)"; \
		exit 1; \
	fi; \
	VERSION=$$("$(CADDY_BIN)" version); \
	echo "✔ Caddy verified with rate_limit plugin: $$VERSION"; \
	echo "version=$$VERSION installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee "$(STAMP_CADDY)" >/dev/null; \
	\
	echo "🚀 Applying Caddy service"; \
	$(run_as_root) systemctl enable caddy; \
	if $(run_as_root) systemctl is-active --quiet caddy; then \
		$(run_as_root) systemctl reload caddy && echo "✅ Reload successful"; \
	else \
		$(run_as_root) systemctl start caddy && echo "✅ Started successfully"; \
	fi
	@$(MAKE) deploy-caddy

.PHONY: caddy-validate caddy-fmt

caddy-validate:
	@if [ ! -f /etc/ssl/caddy/fullchain.pem ]; then \
	  echo "[caddy] WARNING: certs missing; skipping full validation"; \
	  echo "[caddy] Run 'make deploy-caddy' or 'make all-caddy' once to install certs."; \
	  exit 0; \
	fi
	@echo "[caddy] validating Caddyfile"
	@sudo caddy validate --config "$(SRC_CADDYFILE)"

caddy-fmt:
	@echo "[caddy] formatting Caddyfile"
	@sudo caddy fmt --overwrite "$(SRC_CADDYFILE)"

.PHONY: assert-caddy-ports-free
assert-caddy-ports-free: ensure-run-as-root
	@conflict=$$($(run_as_root) ss -H -tlnp '( sport = :80 or sport = :443 )' | grep -v caddy || true); \
	if [ -n "$$conflict" ]; then \
		echo "❌ ERROR: Port 80 or 443 is already in use:"; \
		echo "$$conflict"; \
		echo ""; \
		echo "👉 UGOS nginx is likely still redirecting these ports."; \
		echo ""; \
		echo "Please go to:"; \
		echo "  Control Panel → Device Connection → Portal Settings"; \
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
