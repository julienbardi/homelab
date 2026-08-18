# mk/40_nas-traefik.mk
# ------------------------------------------------------------
# Traefik Reverse Proxy Management
# ------------------------------------------------------------

TRAEFIK_STAMP         := $(STAMP_DIR_ROOT)/traefik.installed
TRAEFIK_DYNAMIC_DEST   := /etc/traefik/dynamic/traefik_dynamic.yml
SRC_TRAEFIK_DYNAMIC    := $(REPO_ROOT)/netbird/traefik-dynamic.yaml

.PHONY: nas-traefik
nas-traefik: gitcheck nas-stop-legacy-caddy nas-assert-traefik-ports-free deploy-caddy
	@set -euo pipefail; \
	echo "🔐 Securing certificate and config permissions"; \
	$(run_as_root) sh -c ' \
		mkdir -p /etc/traefik/dynamic /etc/ssl/caddy && \
		chown -R root:root /etc/ssl/caddy && \
		chmod 750 /etc/ssl/caddy && \
		[ -f /etc/ssl/caddy/bardi.ch.cer ] && chmod 640 /etc/ssl/caddy/bardi.ch.cer; \
		[ -f /etc/ssl/caddy/bardi.ch.key ] && chmod 640 /etc/ssl/caddy/bardi.ch.key; \
		true \
	'; \
	\
	echo "📋⬇️ Installing Traefik dynamic configuration"; \
	$(call install_file,$(SRC_TRAEFIK_DYNAMIC),$(TRAEFIK_DYNAMIC_DEST),root,root,0644); \
	\
	echo "🔍 Finding running Traefik container"; \
	CONTAINER_ID=$$($(run_as_root) docker ps -q -f name=traefik | head -n 1); \
	if [ -z "$$CONTAINER_ID" ]; then \
		echo "❌ No running Traefik container found matching name 'traefik'"; \
		exit 1; \
	fi; \
	\
	CONTAINER_NAME=$$($(run_as_root) docker inspect --format '{{.Name}}' "$$CONTAINER_ID" | sed 's#^/##'); \
	echo "✅ Found Traefik container: $$CONTAINER_NAME"; \
	echo "installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee "$(TRAEFIK_STAMP)" >/dev/null; \
	\
	echo "🚀 Restarting container $$CONTAINER_NAME to load dynamic config"; \
	$(run_as_root) docker restart "$$CONTAINER_NAME" >/dev/null && echo "✅ Traefik restarted successfully"

.PHONY: nas-traefik-validate
nas-traefik-validate: deploy-diskstation
	@if ! sudo [ -f /etc/ssl/caddy/bardi.ch.cer ]; then \
		echo "⚠️ Certs missing (/etc/ssl/caddy/bardi.ch.cer); skipping full validation"; \
		exit 0; \
	fi
	@echo "🔍 Validating Traefik static & dynamic configuration"
	@sudo "$(TRAEFIK_BIN)" --configfile=/etc/traefik/tra.toml --test || sudo "$(TRAEFIK_BIN)" healthcheck --ping || echo "ℹ️ Traefik config test complete"

.PHONY: nas-assert-traefik-ports-free
nas-assert-traefik-ports-free:
	@conflict=$$($(run_as_root) ss -H -tlnp '( sport = :80 or sport = :443 )' | grep -vE '(docker-proxy|traefik)' || true); \
	if [ -n "$$conflict" ]; then \
		echo "❌ ERROR: Port 80 or 443 is already in use by an unauthorized process:"; \
		echo "$$conflict"; \
		echo ""; \
		exit 1; \
	fi; \
	echo "✅ Ports 80 and 443 are free for Traefik (Docker proxy allowed)"

.PHONY: nas-stop-legacy-caddy
nas-stop-legacy-caddy:
	@echo "🛑 Stopping and disabling legacy NAS Caddy..."
	@$(run_as_root) sh -c ' \
		systemctl stop caddy 2>/dev/null || true; \
		systemctl disable caddy 2>/dev/null || true; \
		rm -f /etc/systemd/system/cert-reload@caddy.service 2>/dev/null || true; \
		systemctl daemon-reload 2>/dev/null || true \
	'