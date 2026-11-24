# mk/85_netbird.mk — Included by top-level Makefile

# Correct NetBird directory path
NETBIRD_DIR := $(REPO_ROOT)/netbird

NETBIRD_COMPOSE_FILE := $(NETBIRD_DIR)/docker-compose.yml
NETBIRD_TEMPLATE_FILE := $(NETBIRD_DIR)/config.yaml.template
NETBIRD_CONFIG_FILE  := $(NETBIRD_DIR)/config.yaml

COMPOSE_NETBIRD := docker compose -p netbird -f $(NETBIRD_COMPOSE_FILE)

# Shadow files (user-level)
NETBIRD_COMPOSE_SHADOW := $(STAMP_DIR_USER)/netbird_compose.shadow
NETBIRD_CONFIG_SHADOW  := $(STAMP_DIR_USER)/netbird_config.shadow

# Restart stamps
NETBIRD_RESTART_STAMP := $(STAMP_DIR_USER)/netbird_restart.stamp

###############################################################################
# NetBird Proxy Token Rotation
###############################################################################
.PHONY: netbird-rotate-token
netbird-rotate-token: ensure-state-dirs
	@echo "🔄 Token rotation requested — scheduling NetBird stack redeploy..."
	@touch $(NETBIRD_RESTART_STAMP)

###############################################################################
# NetBird compose + config deployment (idempotent)
###############################################################################

.PHONY: render-netbird-config
render-netbird-config: enforce-groups | $(run_as_root)
	@$(call require_file,$(NETBIRD_TEMPLATE_FILE))
	@$(call WITH_SECRETS, \
		command -v envsubst >/dev/null 2>&1 || { \
			echo "❌ Missing required tool: envsubst"; \
			exit 1; \
		}; \
		case "$$netbird_auth_secret" in \
			""|null) \
				echo "❌ netbird_auth_secret is missing or null"; \
				exit 1; \
				;; \
		esac; \
		case "$$netbird_encryption_key" in \
			""|null) \
				echo "❌ netbird_encryption_key is missing or null"; \
				exit 1; \
				;; \
		esac; \
		[ "$(VERBOSE)" -lt "1" ] || \
			echo "📝 Rendering NetBird config from template..."; \
		tmp="$$(mktemp)"; \
		trap 'rm -f "$$tmp"' EXIT; \
		export NB_AUTH_SECRET="$$netbird_auth_secret"; \
		export NB_ENCRYPTION_KEY="$$netbird_encryption_key"; \
		envsubst '$$NB_AUTH_SECRET $$NB_ENCRYPTION_KEY' \
			< "$(NETBIRD_TEMPLATE_FILE)" \
			> "$$tmp"; \
		[ -s "$$tmp" ] || { \
			echo "❌ Rendered NetBird config is empty"; \
			exit 1; \
		}; \
		$(call install_file,"$$tmp",$(NETBIRD_CONFIG_FILE),$(shell id -u),$(shell id -g),0640) || { \
			rc=$$?; \
			[ "$$rc" -eq "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ] || exit "$$rc"; \
		}; \
		$(run_as_root) sh -eu -c 'chgrp admins "$(NETBIRD_CONFIG_FILE)"; chmod 0640 "$(NETBIRD_CONFIG_FILE)";'; \
	)

.PHONY: deploy-netbird-compose
deploy-netbird-compose: \
	render-netbird-config $(NETBIRD_COMPOSE_FILE) ensure-state-dirs enforce-groups | $(run_as_root)
	@$(call require_file,$(NETBIRD_COMPOSE_FILE))
	@$(call require_file,$(NETBIRD_CONFIG_FILE))
	@if [ "$(VERBOSE)" -ge "1" ]; then echo "📦 Checking NetBird compose + config changes..."; fi; \
	changed=0; rc=0; \
	$(call install_file,$(NETBIRD_COMPOSE_FILE),$(NETBIRD_COMPOSE_SHADOW),$(shell id -u),$(shell id -g),0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 docker-compose.yml changed — scheduling NetBird restart"; \
		touch $(NETBIRD_RESTART_STAMP); \
	fi; \
	\
	changed=0; rc=0; \
	$(call install_file,$(NETBIRD_CONFIG_FILE),$(NETBIRD_CONFIG_SHADOW),$(shell id -u),$(shell id -g),0640) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	$(run_as_root) sh -eu -c 'chgrp admins "$(NETBIRD_CONFIG_SHADOW)"; chmod 0640 "$(NETBIRD_CONFIG_SHADOW)";'; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 config.yaml changed — scheduling NetBird restart"; \
		touch $(NETBIRD_RESTART_STAMP); \
	fi

###############################################################################
# NetBird stack deployment (idempotent & zero-at-rest secrets)
###############################################################################

.PHONY: netbird-deploy
netbird-deploy: docker-daemon deploy-nas-caddyfile deploy-netbird-compose
	@$(call require_file,$(NETBIRD_COMPOSE_FILE))
	@$(call require_file,$(NETBIRD_CONFIG_FILE))
	@if [ ! -f "$(NETBIRD_RESTART_STAMP)" ]; then \
		[ "$(VERBOSE)" -lt "1" ] || echo "🟢 NetBird already up-to-date"; \
	else \
		$(call WITH_SECRETS, \
			echo "🧹 Cleaning up any existing NetBird stack..."; \
			$(COMPOSE_NETBIRD) down --remove-orphans 2>/dev/null || true; \
			\
			export LAN_ROUTER="$(LAN_ROUTER)"; \
			export LAN_NAS="$(LAN_NAS)"; \
			export INFOMANIAK_ACCESS_TOKEN="$$infomaniak_api_token"; \
			export ACME_EMAIL="$$acme_email"; \
			export NB_PROXY_DOMAIN="$$ddns_netbird_domain"; \
			export NB_PROXY_TOKEN="$$netbird_proxy_token"; \
			\
			echo "🚀 Ensuring NetBird server is running..."; \
			$(COMPOSE_NETBIRD) up -d netbird-server; \
			\
			for i in $$(seq 1 30); do \
				if docker exec netbird-server true >/dev/null 2>&1; then \
					break; \
				fi; \
				sleep 1; \
			done; \
			\
			docker exec netbird-server true >/dev/null 2>&1 || { \
				echo "❌ netbird-server failed to become ready"; \
				exit 1; \
			}; \
			\
			if [ -z "$$NB_PROXY_TOKEN" ] || [ "$$NB_PROXY_TOKEN" = "null" ]; then \
				echo "🔐 Generating proxy token in RAM..."; \
				TOKEN_OUTPUT=$$(docker exec -i netbird-server /go/bin/netbird-server --config /etc/netbird/config.yaml admin token create --name proxy-token-$$(date +%s)) && \
				export NB_PROXY_TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep "Token:" | awk '{print $$2}'); \
			fi; \
			\
			if [ -z "$$NB_PROXY_TOKEN" ]; then \
				echo "❌ Error: Could not obtain NB_PROXY_TOKEN"; \
				exit 1; \
			fi; \
			\
			echo "📦 Applying full docker compose stack with in-memory secrets..."; \
			$(COMPOSE_NETBIRD) up -d; \
			rm -f $(NETBIRD_RESTART_STAMP) \
		); \
	fi

###############################################################################
# Convenience targets
###############################################################################

.PHONY: netbird-up
netbird-up: netbird-deploy

.PHONY: netbird-down
netbird-down:
	@$(call require_file,$(NETBIRD_COMPOSE_FILE))
	@echo "🛑 Stopping NetBird stack..."
	@$(COMPOSE_NETBIRD) down

.PHONY: netbird-restart
netbird-restart:
	@$(call require_file,$(NETBIRD_COMPOSE_FILE))
	@echo "🔄 Restarting NetBird stack..."
	@$(COMPOSE_NETBIRD) restart

.PHONY: netbird-logs
netbird-logs:
	@$(call require_file,$(NETBIRD_COMPOSE_FILE))
	@$(COMPOSE_NETBIRD) logs -f

.PHONY: netbird-reset
netbird-reset:
	@rm -f $(NETBIRD_COMPOSE_SHADOW) $(NETBIRD_CONFIG_SHADOW) $(NETBIRD_RESTART_STAMP)

.PHONY: netbird-nuke
netbird-nuke:
	@$(call require_file,$(NETBIRD_COMPOSE_FILE))
	@echo "☢️ Destroying NetBird persistent state..."
	@$(COMPOSE_NETBIRD) down --remove-orphans

	@docker volume rm netbird_netbird_data 2>/dev/null || true

	@rm -f \
		$(NETBIRD_COMPOSE_SHADOW) \
		$(NETBIRD_CONFIG_SHADOW) \
		$(NETBIRD_RESTART_STAMP)

.PHONY: netbird-upgrade
netbird-upgrade: docker-daemon
	@$(call require_file,$(NETBIRD_COMPOSE_FILE))

	@echo "⬇️ Pulling latest NetBird images..."
	@$(COMPOSE_NETBIRD) pull

	@echo "🔄 Recreating NetBird containers..."
	@$(COMPOSE_NETBIRD) up -d --force-recreate \
		netbird-server \
		dashboard \
		crowdsec

.PHONY: netbird-pve-install
netbird-pve-install: | $(run_as_root)
	curl -fsSL https://pkgs.netbird.io/install.sh | $(run_as_root) bash

.PHONY: netbird-pve-enroll
netbird-pve-enroll:
	@echo "⚠️ Run: sudo netbird profile claim default"
	@echo "⚠️ Requires interactive SSO login"
	netbird up --management-url https://netbird.bardi.ch

.PHONY: netbird-pve-exitnode

netbird-pve-exitnode: | $(run_as_root)
	@echo "⚠️ Enable exit-node routing in NetBird after enrollment"
	@$(run_as_root) sysctl \
		net.ipv4.ip_forward=1 \
		net.ipv6.conf.all.forwarding=1 >/dev/null
