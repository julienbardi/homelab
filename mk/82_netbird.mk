# ============================================================
# mk/82_netbird.mk — NetBird control plane (self-hosted)
#
# - System-level convergence (uses /var/lib/homelab)
# - Declarative config in config/netbird/
# - Simple plan/apply/status/clean targets
# - No stamp files, no hash files, no directory targets
# ============================================================

# default stamp root (can be overridden by top-level Makefile)
STAMP_DIR ?= .state

NETBIRD_CONFIG_DIR    := config/netbird
NETBIRD_STATE_ROOT    := $(STAMP_DIR)/netbird          # /var/lib/homelab/netbird

NETBIRD_COMPOSE_FILE  := $(NETBIRD_CONFIG_DIR)/docker-compose.netbird.yaml
NETBIRD_DOMAIN_FILE   := $(NETBIRD_CONFIG_DIR)/management-url
NETBIRD_SETUP_KEY_FILE:= $(NETBIRD_CONFIG_DIR)/setup-key

NETBIRD_GROUPS_YAML   := $(NETBIRD_CONFIG_DIR)/groups.yaml
NETBIRD_POLICIES_YAML := $(NETBIRD_CONFIG_DIR)/policies.yaml
NETBIRD_ROUTES_YAML   := $(NETBIRD_CONFIG_DIR)/routes.yaml

NETBIRDCTL            := /usr/local/bin/netbirdctl

# Ensure host config files exist and optionally install netbirdctl
NETBIRD_HOST_CONFIG_DIR := /etc/netbird
REPO_CONFIG_DIR := $(NETBIRD_CONFIG_DIR)

.PHONY: netbird-ensure-config install-netbirdctl

netbird-ensure-config:
	@echo "Ensuring $(NETBIRD_HOST_CONFIG_DIR) exists and required files are present..."
	@sudo mkdir -p $(NETBIRD_HOST_CONFIG_DIR)
	# copy repo-provided management.json if present, otherwise create a safe default file
	@if [ -f "$(REPO_CONFIG_DIR)/management.json" ]; then \
	  echo "Using repo management.json"; \
	  sudo cp "$(REPO_CONFIG_DIR)/management.json" "$(NETBIRD_HOST_CONFIG_DIR)/management.json"; \
	else \
	  echo "Creating management.json with sqlite DB path"; \
	  sudo printf '%s\n' '{' '  "server": { "listen": "0.0.0.0:33075" },' '  "database": { "type": "sqlite", "path": "/var/lib/netbird/management.db" }' '}' > /tmp/nb_mgmt.json; \
	  sudo mv /tmp/nb_mgmt.json "$(NETBIRD_HOST_CONFIG_DIR)/management.json"; \
	fi
	# copy repo-provided relay.json if present, otherwise create one with exposed_address set to host primary IP
	@if [ -f "$(REPO_CONFIG_DIR)/relay.json" ]; then \
	  echo "Using repo relay.json"; \
	  sudo cp "$(REPO_CONFIG_DIR)/relay.json" "$(NETBIRD_HOST_CONFIG_DIR)/relay.json"; \
	else \
	  HOST_IP="$$(hostname -I | awk '{print $$1}')"; \
	  echo "Creating relay.json with exposed_address=$$HOST_IP"; \
	  sudo printf '%s\n' '{' '  "exposed_address": "'$$HOST_IP'",' '  "ports": { "signal": 33075, "stun": 3478 }' '}' > /tmp/nb_relay.json; \
	  sudo mv /tmp/nb_relay.json "$(NETBIRD_HOST_CONFIG_DIR)/relay.json"; \
	fi
	# ensure DB dir exists and is accessible to the service
	@sudo mkdir -p /var/lib/netbird
	@sudo chown -R root:root /var/lib/netbird
	@sudo chmod 755 /var/lib/netbird
	# secure files (make readable by container processes)
	@sudo chown -R root:root $(NETBIRD_HOST_CONFIG_DIR)
	@sudo chmod 644 $(NETBIRD_HOST_CONFIG_DIR)/*.json || true
	@echo "NetBird host config ensured."
	# create a small docker-compose override to bind host config and DB into containers
	@if [ ! -f "$(NETBIRD_CONFIG_DIR)/docker-compose.netbird.override.yaml" ]; then \
		echo "Creating compose override to mount /etc/netbird and /var/lib/netbird into services"; \
		sudo printf '%s\n' 'version: "3.8"' 'services:' '  management:' '    volumes:' '      - /etc/netbird:/etc/netbird:ro' '      - /var/lib/netbird:/var/lib/netbird:rw' '  relay:' '    volumes:' '      - /etc/netbird:/etc/netbird:ro' '      - /var/lib/netbird:/var/lib/netbird:rw' > /tmp/nb_compose_override.yaml; \
		sudo mv /tmp/nb_compose_override.yaml "$(NETBIRD_CONFIG_DIR)/docker-compose.netbird.override.yaml"; \
		sudo chown root:root "$(NETBIRD_CONFIG_DIR)/docker-compose.netbird.override.yaml"; \
		sudo chmod 644 "$(NETBIRD_CONFIG_DIR)/docker-compose.netbird.override.yaml"; \
	else \
		echo "Compose override already present"; \
	fi

install-netbirdctl:
	@echo "Installing netbirdctl to $(NETBIRDCTL) if missing..."
	@if [ ! -x "$(NETBIRDCTL)" ]; then \
	  ARCH="$$(uname -m)"; \
	  case "$$ARCH" in \
		x86_64) BIN="netbirdctl_linux_amd64";; \
		aarch64|arm64) BIN="netbirdctl_linux_arm64";; \
		*) echo "Unsupported arch $$ARCH; install netbirdctl manually"; exit 1;; \
	  esac; \
	  sudo curl -fsSL -o "$(NETBIRDCTL)" "https://github.com/netbirdio/netbird/releases/latest/download/$$BIN"; \
	  sudo chmod +x "$(NETBIRDCTL)"; \
	else \
	  echo "netbirdctl already present"; \
	fi

.PHONY: netbird-plan netbird-apply netbird-status netbird-clean \
		netbird-bootstrap netbird-compose-apply netbird-up \
		netbird-sync-groups netbird-sync-policies netbird-sync-routes

# ------------------------------------------------------------
# Bootstrap: ensure NetBird stack + config are in place
# (phony; does not create stamp files or directories as targets)
# ------------------------------------------------------------
.PHONY: netbird-bootstrap
netbird-bootstrap: $(NETBIRD_COMPOSE_FILE) $(INSTALL_FILES_IF_CHANGED) netbird-ensure-config
	@echo "🧩 Bootstrapping NetBird control plane (systemd units + state root)"
	@$(run_as_root) mkdir -p "$(NETBIRD_STATE_ROOT)"
	@$(run_as_root) mkdir -p /etc/systemd/system

	@echo "🛠️ Installing NetBird systemd units (IFC v2) — explicit calls"
	@set +e; CHANGED=0; \
	for svc in management signal relay stun; do \
	  SRC="config/systemd/netbird-$$svc.service"; \
	  DST="/etc/systemd/system/netbird-$$svc.service"; \
	  $(run_as_root) env CHANGED_EXIT_CODE=3 /usr/local/bin/install_file_if_changed_v2.sh "" "" "$$SRC" "" "" "$$DST" "root" "root" "0644"; rc=$$?; \
	  if [ $$rc -eq 3 ]; then \
		CHANGED=1; \
		echo "🔄 $$DST updated"; \
	  elif [ $$rc -ne 0 ]; then \
		echo "[install_files_if_changed_v2] failed for $$DST (rc=$$rc)"; \
		exit $$rc; \
	  else \
		echo "⚪ $$DST up-to-date"; \
	  fi; \
	done; \
	if [ $$CHANGED -eq 1 ]; then \
	  echo "🔄 Systemd units changed — reloading daemon"; \
	  $(run_as_root) systemctl daemon-reload; \
	fi; set -e

	@$(run_as_root) systemctl enable netbird-management.service || true
	@$(run_as_root) systemctl enable netbird-signal.service || true
	@$(run_as_root) systemctl enable netbird-relay.service || true
	@$(run_as_root) systemctl enable netbird-stun.service || true

# ------------------------------------------------------------
# Compose apply (phony)
# ------------------------------------------------------------
.PHONY: netbird-compose-apply
	netbird-compose-apply: netbird-bootstrap
	# start services using the main compose file plus the override (if present)
	@if [ -f "$(NETBIRD_CONFIG_DIR)/docker-compose.netbird.override.yaml" ]; then \
		echo "Using compose override for host mounts"; \
		$(run_as_root) systemctl stop netbird-management.service || true; \
		$(run_as_root) systemctl stop netbird-signal.service || true; \
		$(run_as_root) systemctl stop netbird-relay.service || true; \
		$(run_as_root) systemctl stop netbird-stun.service || true; \
		$(run_as_root) /usr/bin/docker compose -f "$(NETBIRD_COMPOSE_FILE)" -f "$(NETBIRD_CONFIG_DIR)/docker-compose.netbird.override.yaml" up -d management signal relay stun || true; \
	else \
		$(run_as_root) systemctl start netbird-management.service || true; \
		$(run_as_root) systemctl start netbird-signal.service || true; \
		$(run_as_root) systemctl start netbird-relay.service || true; \
		$(run_as_root) systemctl start netbird-stun.service || true; \
	fi

	@echo "🔄 Restarting NetBird services (apply override if present)"
	@if [ -f "$(NETBIRD_CONFIG_DIR)/docker-compose.netbird.override.yaml" ]; then \
		$(run_as_root) /usr/bin/docker compose -f "$(NETBIRD_COMPOSE_FILE)" -f "$(NETBIRD_CONFIG_DIR)/docker-compose.netbird.override.yaml" up -d --remove-orphans || true; \
	else \
		$(run_as_root) systemctl restart netbird-management.service || true; \
		$(run_as_root) systemctl restart netbird-signal.service || true; \
		$(run_as_root) systemctl restart netbird-relay.service || true; \
		$(run_as_root) systemctl restart netbird-stun.service || true; \
	fi

# ------------------------------------------------------------
# NetBird "up" (management URL + setup key) (phony)
# ------------------------------------------------------------
.PHONY: netbird-up
netbird-up: netbird-compose-apply $(NETBIRD_DOMAIN_FILE) $(NETBIRD_SETUP_KEY_FILE)
	@echo "🚀 Enrolling NetBird node"
	@mgmt_url="$$(cat "$(NETBIRD_DOMAIN_FILE)")"; \
	setup_key="$$(cat "$(NETBIRD_SETUP_KEY_FILE)")"; \
	$(run_as_root) $(NETBIRDCTL) up --management-url "$$mgmt_url" --setup-key "$$setup_key" || true

# ------------------------------------------------------------
# Groups / policies / routes (phony)
# ------------------------------------------------------------
.PHONY: netbird-sync-groups
netbird-sync-groups: $(NETBIRD_GROUPS_YAML) netbird-up
	@echo "👥 Syncing NetBird groups"
	@$(run_as_root) $(NETBIRDCTL) sync groups "$(NETBIRD_GROUPS_YAML)" || true

.PHONY: netbird-sync-policies
netbird-sync-policies: $(NETBIRD_POLICIES_YAML) netbird-sync-groups
	@echo "🛡️ Syncing NetBird policies"
	@$(run_as_root) $(NETBIRDCTL) sync policies "$(NETBIRD_POLICIES_YAML)" || true

.PHONY: netbird-sync-routes
netbird-sync-routes: $(NETBIRD_ROUTES_YAML) netbird-sync-policies
	@echo "🗺️ Syncing NetBird routes"
	@$(run_as_root) $(NETBIRDCTL) sync routes "$(NETBIRD_ROUTES_YAML)" || true

# ------------------------------------------------------------
# Plan / apply / status / clean
# ------------------------------------------------------------
netbird-plan:
	@echo "📋 NetBird plan (files):"
	@echo "  compose : $(NETBIRD_COMPOSE_FILE)"
	@echo "  groups  : $(NETBIRD_GROUPS_YAML)"
	@echo "  policies: $(NETBIRD_POLICIES_YAML)"
	@echo "  routes  : $(NETBIRD_ROUTES_YAML)"
	@# fail early if required inputs are missing
	@test -f "$(NETBIRD_COMPOSE_FILE)" || (echo "ERROR: missing $(NETBIRD_COMPOSE_FILE)"; false)
	@test -f "$(NETBIRD_DOMAIN_FILE)" || (echo "ERROR: missing $(NETBIRD_DOMAIN_FILE)"; false)
	@test -f "$(NETBIRD_SETUP_KEY_FILE)" || (echo "ERROR: missing $(NETBIRD_SETUP_KEY_FILE)"; false)
	@echo "✅ Plan OK (no stamp files used)."

netbird-apply: netbird-sync-routes
	@echo "✅ NetBird control plane converged (compose + up + groups + policies + routes)"

netbird-status:
	@echo "🔍 NetBird status:"
	@$(run_as_root) $(NETBIRDCTL) status || true
	@echo "📂 NetBird state root:"
	@$(run_as_root) ls -l "$(NETBIRD_STATE_ROOT)" || true
	@echo "📂 Config files:"
	@ls -l "$(NETBIRD_CONFIG_DIR)" || true

netbird-clean:
	@echo "🧹 Removing NetBird local NetBird state (state root only, not touching containers)"
	@$(run_as_root) rm -rf "$(NETBIRD_STATE_ROOT)" || true
	@echo "✅ Clean complete."
