# ============================================================
# mk/82_netbird.mk — NetBird control plane (self-hosted)
#
# - System-level convergence (uses /var/lib/homelab)
# - Declarative config in config/netbird/
# - Hash-based drift detection
# - Plan / apply semantics
# - No recursive make, no duplicate writers
# ============================================================

NETBIRD_CONFIG_DIR    := config/netbird
NETBIRD_STATE_ROOT    := $(STAMP_DIR)/netbird          # /var/lib/homelab/netbird
NETBIRD_STAMP_DIR     := $(NETBIRD_STATE_ROOT)/stamps
NETBIRD_HASH_DIR      := $(NETBIRD_STATE_ROOT)/hashes

NETBIRD_COMPOSE_FILE  := $(NETBIRD_CONFIG_DIR)/docker-compose.netbird.yaml
NETBIRD_DOMAIN_FILE   := $(NETBIRD_CONFIG_DIR)/management-url
NETBIRD_SETUP_KEY_FILE:= $(NETBIRD_CONFIG_DIR)/setup-key

NETBIRD_GROUPS_YAML   := $(NETBIRD_CONFIG_DIR)/groups.yaml
NETBIRD_POLICIES_YAML := $(NETBIRD_CONFIG_DIR)/policies.yaml
NETBIRD_ROUTES_YAML   := $(NETBIRD_CONFIG_DIR)/routes.yaml

NETBIRDCTL            := /usr/local/bin/netbirdctl

# Stamps
NETBIRD_BOOTSTRAP_STAMP := $(NETBIRD_STAMP_DIR)/bootstrap.ok
NETBIRD_COMPOSE_STAMP   := $(NETBIRD_STAMP_DIR)/compose.ok
NETBIRD_UP_STAMP        := $(NETBIRD_STAMP_DIR)/up.ok
NETBIRD_GROUPS_STAMP    := $(NETBIRD_STAMP_DIR)/groups.ok
NETBIRD_POLICIES_STAMP  := $(NETBIRD_STAMP_DIR)/policies.ok
NETBIRD_ROUTES_STAMP    := $(NETBIRD_STAMP_DIR)/routes.ok

# Hashes
NETBIRD_COMPOSE_HASH  := $(NETBIRD_HASH_DIR)/docker-compose.netbird.yaml.sha256
NETBIRD_GROUPS_HASH   := $(NETBIRD_HASH_DIR)/groups.yaml.sha256
NETBIRD_POLICIES_HASH := $(NETBIRD_HASH_DIR)/policies.yaml.sha256
NETBIRD_ROUTES_HASH   := $(NETBIRD_HASH_DIR)/routes.yaml.sha256

.PHONY: netbird-plan netbird-apply netbird-status netbird-clean

# ------------------------------------------------------------
# Hash helpers (drift detection)
# ------------------------------------------------------------

$(NETBIRD_HASH_DIR):
	@$(run_as_root) mkdir -p $(NETBIRD_HASH_DIR)

$(NETBIRD_STAMP_DIR):
	@$(run_as_root) mkdir -p $(NETBIRD_STAMP_DIR)

# Generic "hash this file" rule
$(NETBIRD_HASH_DIR)/%.sha256: $(NETBIRD_CONFIG_DIR)/%.yaml | $(NETBIRD_HASH_DIR)
	@echo "🔐 Hashing $<"
	@sha256sum "$<" | $(run_as_root) tee "$@" >/dev/null

# ------------------------------------------------------------
# Bootstrap: ensure NetBird stack + config are in place
# ------------------------------------------------------------

$(NETBIRD_BOOTSTRAP_STAMP): $(NETBIRD_COMPOSE_FILE) $(INSTALL_FILES_IF_CHANGED) | $(NETBIRD_STAMP_DIR)
	@echo "🧩 Bootstrapping NetBird control plane (systemd units + state root)"
	@$(run_as_root) mkdir -p "$(NETBIRD_STATE_ROOT)"
	@$(run_as_root) mkdir -p /etc/systemd/system

	@echo "🛠️ Installing NetBird systemd units (IFC v2)"
	@$(run_as_root) $(INSTALL_FILES_IF_CHANGED) NETBIRD_SYSTEMD \
		"" "" config/systemd/netbird-management.service /etc/systemd/system/netbird-management.service root root 0644 \
		"" "" config/systemd/netbird-signal.service     /etc/systemd/system/netbird-signal.service     root root 0644 \
		"" "" config/systemd/netbird-relay.service      /etc/systemd/system/netbird-relay.service      root root 0644 \
		"" "" config/systemd/netbird-stun.service       /etc/systemd/system/netbird-stun.service       root root 0644

	@rc=$$?; \
	if [ "$$rc" -eq "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
		echo "🔄 Systemd units changed — reloading daemon"; \
		$(run_as_root) systemctl daemon-reload; \
	fi

	@$(run_as_root) systemctl enable netbird-management.service
	@$(run_as_root) systemctl enable netbird-signal.service
	@$(run_as_root) systemctl enable netbird-relay.service
	@$(run_as_root) systemctl enable netbird-stun.service

	@$(run_as_root) touch "$@"


# ------------------------------------------------------------
# Compose drift + apply
# ------------------------------------------------------------

$(NETBIRD_COMPOSE_HASH): $(NETBIRD_COMPOSE_FILE) | $(NETBIRD_HASH_DIR)
	@echo "🔐 Hashing NetBird docker-compose file"
	@sha256sum "$(NETBIRD_COMPOSE_FILE)" | $(run_as_root) tee "$@" >/dev/null

$(NETBIRD_COMPOSE_STAMP): $(NETBIRD_BOOTSTRAP_STAMP) $(NETBIRD_COMPOSE_HASH) | $(NETBIRD_STAMP_DIR)
	@echo "📦 Applying NetBird docker-compose stack via systemd"
	@$(run_as_root) systemctl start netbird-management.service
	@$(run_as_root) systemctl start netbird-signal.service
	@$(run_as_root) systemctl start netbird-relay.service
	@$(run_as_root) systemctl start netbird-stun.service

	@echo "🔄 Restarting NetBird services if compose changed"
	@$(run_as_root) systemctl restart netbird-management.service
	@$(run_as_root) systemctl restart netbird-signal.service
	@$(run_as_root) systemctl restart netbird-relay.service
	@$(run_as_root) systemctl restart netbird-stun.service

	@$(run_as_root) touch "$@"

# ------------------------------------------------------------
# NetBird "up" (management URL + setup key)
# ------------------------------------------------------------

$(NETBIRD_UP_STAMP): $(NETBIRD_COMPOSE_STAMP) $(NETBIRD_DOMAIN_FILE) $(NETBIRD_SETUP_KEY_FILE) | $(NETBIRD_STAMP_DIR)
	@if [ ! -f "$(NETBIRD_UP_STAMP)" ]; then \
		echo "🚀 Enrolling NetBird node"; \
		mgmt_url="$$(cat "$(NETBIRD_DOMAIN_FILE)")"; \
		setup_key="$$(cat "$(NETBIRD_SETUP_KEY_FILE)")"; \
		$(run_as_root) $(NETBIRDCTL) up \
			--management-url "$$mgmt_url" \
			--setup-key "$$setup_key"; \
	fi
	@$(run_as_root) touch "$@"

# ------------------------------------------------------------
# Groups / policies / routes (drift-aware)
# ------------------------------------------------------------

$(NETBIRD_GROUPS_STAMP): $(NETBIRD_GROUPS_YAML) $(NETBIRD_GROUPS_HASH) $(NETBIRD_UP_STAMP) | $(NETBIRD_STAMP_DIR)
	@echo "👥 Syncing NetBird groups"
	@$(run_as_root) $(NETBIRDCTL) sync groups "$(NETBIRD_GROUPS_YAML)"
	@$(run_as_root) touch "$@"

$(NETBIRD_POLICIES_STAMP): $(NETBIRD_POLICIES_YAML) $(NETBIRD_POLICIES_HASH) $(NETBIRD_GROUPS_STAMP) | $(NETBIRD_STAMP_DIR)
	@echo "🛡️ Syncing NetBird policies"
	@$(run_as_root) $(NETBIRDCTL) sync policies "$(NETBIRD_POLICIES_YAML)"
	@$(run_as_root) touch "$@"

$(NETBIRD_ROUTES_STAMP): $(NETBIRD_ROUTES_YAML) $(NETBIRD_ROUTES_HASH) $(NETBIRD_POLICIES_STAMP) | $(NETBIRD_STAMP_DIR)
	@echo "🗺️ Syncing NetBird routes"
	@$(run_as_root) $(NETBIRDCTL) sync routes "$(NETBIRD_ROUTES_YAML)"
	@$(run_as_root) touch "$@"

# ------------------------------------------------------------
# Plan / apply / status / clean
# ------------------------------------------------------------

netbird-plan: \
	$(NETBIRD_COMPOSE_HASH) \
	$(NETBIRD_GROUPS_HASH) \
	$(NETBIRD_POLICIES_HASH) \
	$(NETBIRD_ROUTES_HASH)
	@echo "📋 NetBird plan (hashes):"
	@echo "  compose : $$(cut -d' ' -f1 "$(NETBIRD_COMPOSE_HASH)")"
	@echo "  groups  : $$(cut -d' ' -f1 "$(NETBIRD_GROUPS_HASH)")"
	@echo "  policies: $$(cut -d' ' -f1 "$(NETBIRD_POLICIES_HASH)")"
	@echo "  routes  : $$(cut -d' ' -f1 "$(NETBIRD_ROUTES_HASH)")"
	@echo "🔎 Compare with previous run via git diff or file history."

netbird-apply: \
	$(NETBIRD_ROUTES_STAMP)
	@echo "✅ NetBird control plane converged (compose + up + groups + policies + routes)"

netbird-status:
	@echo "🔍 NetBird status:"
	@$(run_as_root) $(NETBIRDCTL) status || true
	@echo "📂 Stamps in $(NETBIRD_STAMP_DIR):"
	@$(run_as_root) ls -1 "$(NETBIRD_STAMP_DIR)" || true

netbird-clean:
	@echo "🧹 Removing NetBird local NetBird state (stamps + hashes, not touching containers)"
	@$(run_as_root) rm -rf "$(NETBIRD_STATE_ROOT)"
