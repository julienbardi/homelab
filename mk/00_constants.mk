# mk/00_constants.mk
# ============================================================================
# PURPOSE:
#   Global declarative constants for the Homelab Make DAG.
#
#   Deterministic Declarative Architecture (DDA):
#     - All policy is centralized here.
#     - No secrets, no dynamic ingestion, no environment loading.
#     - No logic, no mutation, no side effects.
#     - Modules consume these constants but never redefine them.
#
#   Guarantees:
#     - Reproducible builds
#     - Deterministic behavior
#     - Zero drift between policy and enforcement
#     - Strict separation of policy (here) and logic (modules)
#
#   This file defines:
#     - Identities (admins, service accounts)
#     - Groups and privilege boundaries
#     - Public keys and non-secret configuration
#     - Version pins for local tooling
#     - Canonical host lists
#
#   This file MUST remain:
#     - Purely declarative
#     - Side-effect free
#     - Stable and auditable
# ============================================================================

# ----------------------------------------------------------------------------
# 0. Canonical SSH Known Hosts (Policy)
# ----------------------------------------------------------------------------
# These hosts are enforced by mk/10_groups.mk (Make-native known_hosts logic).
KNOWN_HOSTS := \
	127.0.0.1:2222 \
	10.89.12.1:2222 \
	10.89.12.2:2222 \
	10.89.12.3:2222 \
	10.89.12.4:2222

# ----------------------------------------------------------------------------
# 1. Operator Identity (Dynamic build-time discovery)
# ----------------------------------------------------------------------------
OPERATOR_USER  := $(shell id -un)
OPERATOR_GROUP := $(shell id -gn)
OPERATOR_HOME  := $(shell getent passwd $(OPERATOR_USER) | cut -d: -f6)

# ----------------------------------------------------------------------------
# 2. Global Security Policy (Admins, Groups, Service Accounts)
# ----------------------------------------------------------------------------

# Human operators allowed to mutate system state
AUTHORIZED_ADMINS := julie

# Human-admin groups (must exist; enforced by mk/10_groups.mk)
ADMIN_GROUPS := systemd-journal docker sudo adm dnscrypt

# Service-owned groups (no human membership)
SERVICE_GROUPS := headscale _dnsdist ssl-cert dnswarm

# Service accounts (user:primary_group)
SERVICE_MAP := \
	headscale:headscale \
	_dnsdist:_dnsdist \
	dnswarm:dnswarm

# Authorization guard (used by multiple modules)
.PHONY: ensure-authorized-admin
ensure-authorized-admin:
	@echo "$(AUTHORIZED_ADMINS)" | grep -qw "$(OPERATOR_USER)" || \
		{ echo "❌ User $(OPERATOR_USER) not authorized for this mutation"; exit 1; }

# ----------------------------------------------------------------------------
# 3. Root Ownership Defaults (Overrideable)
# ----------------------------------------------------------------------------
ROOT_UID  := $(shell id -u root 2>/dev/null || echo 0)
ROOT_GID  := $(shell id -g root 2>/dev/null || echo 0)
ROOT_HOME := $(shell getent passwd root | cut -d: -f6)

# ----------------------------------------------------------------------------
# 4. State / Stamp Directory Configuration
# ----------------------------------------------------------------------------
XDG_STATE_HOME := $(HOME)/.local/state
STAMP_DIR_USER := $(XDG_STATE_HOME)/homelab
STAMP_DIR_ROOT := /var/lib/homelab

.PHONY: ensure-stamp-dir
ensure-stamp-dir:
	@mkdir -p "$(STAMP_DIR)"
	@if [ "$(STAMP_DIR)" = "$(STAMP_DIR_ROOT)" ]; then \
		$(run_as_root) install -d -m 0755 "$(STAMP_DIR)"; \
		$(run_as_root) chown root:root "$(STAMP_DIR)" || true; \
	else \
		install -d -m 0755 "$(STAMP_DIR)"; \
	fi

# ----------------------------------------------------------------------------
# 5. Documentation Directory (Deferred assignment)
# ----------------------------------------------------------------------------
DOCS_DIR = $(INSTALL_PATH)/docs

# ----------------------------------------------------------------------------
# 6. Tooling Definitions (Blueprints vs. Artifacts)
# ----------------------------------------------------------------------------

# BLUEPRINTS — always present in the Git repo
RUN_ROOT_SRC      := $(REPO_ROOT)/scripts/run-as-root.sh
IFC_V2_SINGLE_SRC := $(REPO_ROOT)/scripts/install_file_if_changed_v2.sh
IFC_V2_PLURAL_SRC := $(REPO_ROOT)/scripts/install_files_if_changed_v2.sh
IFC_URL_SRC       := $(REPO_ROOT)/scripts/install_url_file_if_changed.sh
COMMON_SRC        := $(REPO_ROOT)/scripts/common.sh

# ARTIFACTS — installed system locations
export run_as_root                 := $(INSTALL_SBIN_PATH)/run-as-root.sh
export INSTALL_FILE_IF_CHANGED     := $(INSTALL_PATH)/install_file_if_changed_v2.sh
export INSTALL_FILES_IF_CHANGED    := $(INSTALL_PATH)/install_files_if_changed_v2.sh
export INSTALL_URL_FILE_IF_CHANGED := $(INSTALL_PATH)/install_url_file_if_changed.sh

# ----------------------------------------------------------------------------
# 7. Build Invariants
# ----------------------------------------------------------------------------
N_WORKERS := $(shell nproc | awk '{print ($$1 > 1 ? $$1 - 1 : 1)}')
INSTALL_IF_CHANGED_EXIT_CHANGED ?= 3

# ----------------------------------------------------------------------------
# 8. Router Mappings (Non-secret)
# ----------------------------------------------------------------------------
SRC_SCRIPTS          := $(REPO_ROOT)/router/jffs/scripts
ROUTER_CADDYFILE_SRC := $(REPO_ROOT)/router/caddy/Caddyfile
ROUTER_CADDYFILE_DST := /jffs/caddy/Caddyfile

ROUTER_CADDY_VERSION ?= 2.11.2
ROUTER_CADDY_ARCH    ?= linux_arm64
ROUTER_CADDY_URL     := https://github.com/caddyserver/caddy/releases/download/v$(ROUTER_CADDY_VERSION)/caddy_$(ROUTER_CADDY_VERSION)_$(ROUTER_CADDY_ARCH).tar.gz
ROUTER_CADDY_BIN     := /tmp/mnt/sda/router/bin/caddy
ROUTER_CADDY_STAMP   := /jffs/.stamps/caddy.installed
ROUTER_CADDY_SHA256  := b9d88bec4254d0a98bd415ad60f97f37e4222dec96235c00b442437f5e303a32

COMMON_SH_DST        := $(ROUTER_SCRIPTS)/common.sh

CERTS_CREATE       := $(ROUTER_SCRIPTS)/certs-create.sh
CERTS_DEPLOY       := $(ROUTER_SCRIPTS)/deploy_certificates.sh
GEN_CLIENT_CERT    := $(ROUTER_SCRIPTS)/generate-client-cert.sh
GEN_CLIENT_WRAPPER := $(ROUTER_SCRIPTS)/gen-client-cert-wrapper.sh

# ----------------------------------------------------------------------------
# 9. Security & Identity (Public key only — no secrets)
# ----------------------------------------------------------------------------
SOPS_AGE_PUBKEY := age1rzyyxnn2ejkchp4jewdpw92av689wdtj2kgrv3ys4p3chn862vjqc3fs5n

# ----------------------------------------------------------------------------
# 10. SSH Configuration for Router (Non-secret)
# ----------------------------------------------------------------------------
SSH_OPTS   := -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new
#ROUTER_SSH := ssh $(SSH_OPTS)

# ----------------------------------------------------------------------------
# 11. Local Tooling Policy (Declarative Only)
# ----------------------------------------------------------------------------
# These values are consumed by mk/10_local-tools.mk (logic module).
# No logic or mutation belongs here — only policy.

# yq GitHub repository and asset
YQ_GITHUB_REPO := mikefarah/yq
YQ_ASSET       := yq_linux_amd64
YQ_STAMP := $(STAMP_DIR_USER)/yq.installed

# yq version policy:
#   - Set to a pinned version (e.g. v4.53.2)
#   - Or set to latest to always track upstream
YQ_VERSION ?= v4.53.2

YQ_URL := https://github.com/$(YQ_GITHUB_REPO)/releases/download/$(YQ_VERSION)/$(YQ_ASSET)

# Expected SHA256 for pinned version (ignored when using latest)
YQ_SHA256 ?= d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b

# Router identity (from secrets)
ROUTER_USER := $(router_user)
ROUTER_ADDR := $(router_addr)
ROUTER_SSH_PORT := $(router_ssh_port)

# Construct full SSH host
ROUTER_HOST := $(ROUTER_USER)@$(ROUTER_ADDR)

# ----------------------------------------------------------------------------
# Ephemeral DDNS temp (RAM-only, per-user, per-invocation)
# ----------------------------------------------------------------------------
TMP_DDNS_DIR := /run/user/$(shell id -u)/homelab/ddns/$$PPID
TMP_DDNS_CONF := $(TMP_DDNS_DIR)/.ddns_confidential
