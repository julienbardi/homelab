# mk/00_constants.mk
# ============================================================================
# PURPOSE:
#   Declarative logic and Repo-to-System mappings.
#   Data (IPs, Paths, Roles) lives in homelab.env.
# ============================================================================

# 1. Operator identity (Dynamic build-time discovery)
OPERATOR_USER  := $(shell id -un)
OPERATOR_GROUP := $(shell id -gn)
OPERATOR_HOME  := $(shell getent passwd $(OPERATOR_USER) | cut -d: -f6)

# Defaults for root ownership (overrideable)
ROOT_UID := $(shell id -u root 2>/dev/null || echo 0)
ROOT_GID := $(shell id -g root 2>/dev/null || echo 0)
ROOT_HOME := $(shell getent passwd root | cut -d: -f6)

# State/stamp directory configuration (overrideable)
# Default to per-user $(HOME)/.local/state/homelab; allow SYSTEM_WIDE=1 to use /var/lib/homelab
XDG_STATE_HOME := $(HOME)/.local/state
STAMP_DIR_USER := $(XDG_STATE_HOME)/homelab
STAMP_DIR_ROOT := /var/lib/homelab

# 2. Ingest the Data Source
HOMELAB_ENV_DST := /volume1/homelab/homelab.env

# --- 3. The Self-Healing Include ---

# Initial guess based on file presence
BOOTSTRAP := $(if $(wildcard $(HOMELAB_ENV_DST)),,1)

# Ingest the Data
-include $(HOMELAB_ENV_DST)

# Use deferred assignment (=) so it picks up INSTALL_PATH
# AFTER the include above has processed.
DOCS_DIR = $(INSTALL_PATH)/docs

# If the include worked and we have a DOMAIN, we are NO LONGER bootstrapping.
ifneq ($(strip $(DOMAIN)),)
	BOOTSTRAP :=
endif

export BOOTSTRAP

# --- 4. Variable Promotion & Export ---

# 1. PROMOTED VARIABLES:
# We lock these into Make's memory AND export them to the shell in one line.
export DOMAIN            := $(DOMAIN)
export UNBOUND_PORT      := $(UNBOUND_PORT)
export NAS_LAN_IP        := $(NAS_LAN_IP)
export ROUTER_ADDR       := $(ROUTER_ADDR)
export ROUTER_USER       := $(ROUTER_USER)
export INSTALL_PATH      := $(INSTALL_PATH)
export INSTALL_SBIN_PATH := $(INSTALL_SBIN_PATH)

# 2. PASS-THROUGH EXPORTS:
# Purely for child processes; Make does not need to "see" these internally.
export NAS_LAN_IP6
export HOMELAB_DIR
export WG_ROOT

# --- 5. Tooling Definitions (The Blueprint vs. The Artifact) ---

# A. THE BLUEPRINTS (Always available in your Git Repo)
RUN_ROOT_SRC      := $(REPO_ROOT)scripts/run-as-root.sh
IFC_V2_SINGLE_SRC := $(REPO_ROOT)scripts/install_file_if_changed_v2.sh
IFC_V2_PLURAL_SRC := $(REPO_ROOT)scripts/install_files_if_changed_v2.sh
IFC_URL_SRC       := $(REPO_ROOT)scripts/install_url_file_if_changed.sh
COMMON_SRC        := $(REPO_ROOT)scripts/common.sh

# B. THE ARTIFACTS (System locations - safe to be empty during early parse)
# Note: Use deferred assignment (=) or ensure these are only used in recipes
# after BOOTSTRAP logic has had a chance to run or INSTALL_PATH is set.
export run_as_root                 := $(INSTALL_SBIN_PATH)/run-as-root.sh
export INSTALL_FILE_IF_CHANGED     := $(INSTALL_PATH)/install_file_if_changed_v2.sh
export INSTALL_FILES_IF_CHANGED    := $(INSTALL_PATH)/install_files_if_changed_v2.sh
export INSTALL_URL_FILE_IF_CHANGED := $(INSTALL_PATH)/install_url_file_if_changed.sh

# no dependency on ensure-run-as-root as this gets executed by unprivileged users also
.PHONY: ensure-stamp-dir
ensure-stamp-dir:
	@mkdir -p "$(STAMP_DIR)"
	@if [ "$(STAMP_DIR)" = "$(STAMP_DIR_ROOT)" ]; then \
		$(run_as_root) install -d -m 0755 "$(STAMP_DIR)"; \
		$(run_as_root) chown root:root "$(STAMP_DIR)" || true; \
	else \
		install -d -m 0755 "$(STAMP_DIR)"; \
	fi

# --- 6. Enforcing permissions ---
$(HOMELAB_ENV_DST):
	@echo "Enforcing permissions: $@"
	sudo chmod 0644 $@; \
	sudo chown root:root $@; \
	sudo touch $@;

# --- 7. Safety Guards ---
ifeq ($(strip $(BOOTSTRAP)),)
  ifeq ($(strip $(DOMAIN)),)
	CONFIG_ERROR := "DOMAIN is empty — Ensure $(HOMELAB_ENV_DST) is valid."
  endif
  ifeq ($(strip $(UNBOUND_PORT)),)
	CONFIG_ERROR := "UNBOUND_PORT is not defined in $(HOMELAB_ENV_DST)."
  endif
  # Added for LAN health check safety
  ifeq ($(strip $(NAS_LAN_IP)),)
	CONFIG_ERROR := "NAS_LAN_IP is not defined in $(HOMELAB_ENV_DST)."
  endif
endif

## Prefer an explicit ROUTER_HOST if provided; otherwise compute from user + addr.
ifeq ($(strip $(ROUTER_HOST)),)
  export ROUTER_HOST := $(ROUTER_USER)@$(ROUTER_ADDR)
else
  export ROUTER_HOST := $(ROUTER_HOST)
endif
export GATEWAY_IP    := $(ROUTER_ADDR)
export ROUTER_LAN_IP := $(ROUTER_ADDR)

.PHONY: guard-config
guard-config:
	@if [ -n "$(CONFIG_ERROR)" ]; then \
		echo "❌ Configuration Error: $(CONFIG_ERROR)"; \
		exit 1; \
	fi

# Build Invariants
N_WORKERS := $(shell nproc | awk '{print ($$1 > 1 ? $$1 - 1 : 1)}')
INSTALL_IF_CHANGED_EXIT_CHANGED ?= 3

# Router Mappings
SRC_SCRIPTS          := $(REPO_ROOT)router/jffs/scripts
ROUTER_CADDYFILE_SRC := $(REPO_ROOT)router/caddy/Caddyfile
ROUTER_CADDYFILE_DST := /jffs/caddy/Caddyfile
COMMON_SH_DST        := $(ROUTER_SCRIPTS)/common.sh

# Helper script locations on the router
CERTS_CREATE       := $(ROUTER_SCRIPTS)/certs-create.sh
CERTS_DEPLOY       := $(ROUTER_SCRIPTS)/deploy_certificates.sh
GEN_CLIENT_CERT    := $(ROUTER_SCRIPTS)/generate-client-cert.sh
GEN_CLIENT_WRAPPER := $(ROUTER_SCRIPTS)/gen-client-cert-wrapper.sh

# Security & Identity
SOPS_AGE_PUBKEY := age1rzyyxnn2ejkchp4jewdpw92av689wdtj2kgrv3ys4p3chn862vjqc3fs5n

# SSH Configuration for Router
# We use -o StrictHostKeyChecking=accept-new to handle re-installs gracefully
# while maintaining batch mode for non-interactive automation.
SSH_OPTS   := -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new
ROUTER_SSH := ssh $(SSH_OPTS) -p $(ROUTER_SSH_PORT) $(ROUTER_USER)@$(ROUTER_ADDR)