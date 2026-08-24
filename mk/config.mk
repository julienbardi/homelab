# config.mk — committed, non-secret configuration

# LAN Topology (authoritative)
export LAN_NET      := 10.89.12.0/24
export LAN_NET_ADDR := 10.89.12.0
export LAN_ROUTER   := 10.89.12.1
export LAN_SYNOLOGY := 10.89.12.2
export LAN_QNAP     := 10.89.12.3
export LAN_NAS      := 10.89.12.4
export LAN_AC86U    := 10.89.12.6
export LAN_HUB01    := 10.89.12.11

# IPv6 ULA Topology (authoritative)
export LAN6_NET         := fd89:7a3b:42c0::/64
export LAN6_PREFIX_BASE := fd89:7a3b:42c0
export LAN6_PREFIX_LEN  := 48
export LAN6_ROUTER      := fd89:7a3b:42c0::1
export LAN6_SYNOLOGY    := fd89:7a3b:42c0::2
export LAN6_NAS         := fd89:7a3b:42c0::4
export LAN6_AC86U       := fd89:7a3b:42c0::6

export LAN6_PREFIXLEN := 64
# Add others as needed:
# export LAN6_QNAP     := ...

# WireGuard DNS topology (authoritative, non-secret)
# Fastest-first ordering: DoH ➡️ Router IPv4 ➡️ NAS IPv6
export WG_DOH_IPV4       := $(LAN_NAS):8053
export WG_DOH_IPV6       := $(LAN6_NAS):8053
export WG_DNS_ROUTER_IPV4 := $(LAN_ROUTER)
export WG_DNS_NAS_IPV6    := $(LAN6_NAS)

# operator key at make runtime
SSH_PUBLIC_KEY := $(shell cat ~/.ssh/id_ed25519.pub)

# SSH users per host
export SSH_USER_ROUTER   := julie
export SSH_USER_NAS      := julie
export SSH_USER_SYNOLOGY := julie
export SSH_USER_QNAP     := admin
export SSH_USER_AC86U    := admin
export SSH_USER_HUB01    := julie

# SSH host aliases (for ControlMaster reuse)
export SSH_HOST_ROUTER := router
export SSH_HOST_HUB01  := hub01

# SSH options for router access: accept-new not yes so that automation survives router resets
export SSH_OPTS := -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new

ACTUAL_USER := $(or $(SUDO_USER),$(USER))
# Capture the user context
# DDA-Compliant: Resolve home directory via system database instead of hardcoded paths
ACTUAL_HOME := $(or \
	$(shell getent passwd $(ACTUAL_USER) | cut -d: -f6), \
	$(HOME) \
)

# SSH Multiplexing Config
SSH_SOCK_FILE_ROUTER := /tmp/ssh-$(ACTUAL_USER)-router-$(ROUTER_SSH_PORT)

# Bind ROUTER_USER for dns-suite
export ROUTER_USER := $(SSH_USER_ROUTER)

# Paths
export HOMELAB_DIR := $(REPO_ROOT)
export WG_ROOT     := $(HOMELAB_DIR)/wireguard

# System
SYSTEMD_DIR       := /etc/systemd/system
REPO_SYSTEMD      := $(REPO_ROOT)/config/systemd
export INSTALL_PATH      := /usr/local/bin
export INSTALL_SBIN_PATH := /usr/local/sbin

# Network - General
export PUBLIC_DNS := 1.1.1.1

# ------------------------------------------------------------
# Public constants (Make-visible, safe for recipes)
# ------------------------------------------------------------

# 1. Router constants
export ROUTER_ADDR       := 10.89.12.1
export ROUTER_SSH_PORT   := 2222
export ROUTER_ULA_FILE   := /etc/homelab/router-ula
export ROUTER_ULA_VALUE  := fd89:7a3b:42c0::1
export ROUTER_LAN_IFACE  := br0
export ROUTER_WAN_IFACE  := eth0

export ROUTER_IDENTITY   := $(ACTUAL_HOME)/.ssh/id_ed25519

# Router specific paths
export ROUTER_SCRIPTS    := /jffs/scripts
ROUTER_WG_DIR            := /jffs/configs
ROUTER_CADDY_BIN         := /tmp/mnt/sda/router/bin/caddy
ROUTER_CADDY_STAMP       := /jffs/.stamps/caddy.stamp

# Router tooling Metadata
ROUTER_SCRIPTS_OWNER := julie
ROUTER_SCRIPTS_GROUP := root
ROUTER_SCRIPTS_MODE  := 0755

# DHCP Architecture (Declarative Policy)
# Static DHCP reservations: .2 – .99
# Dynamic DHCP pool:        .100 – .254
DHCP_STATIC_MAX    := 99
LAN_PREFIX        := 10.89.12
DHCP_DYNAMIC_START := $(LAN_PREFIX).100
DHCP_DYNAMIC_END   := $(LAN_PREFIX).254

# 2.Synology constants
SYNO_LAN_IFACE := eth0
export SSH_PORT_SYNOLOGY := 2222

# 3. QNAP constants
QNAP_LAN_IFACE := eth0

# 4. NAS constants
# on proxmox vmbr0 , on ugos eth0, see ip -o link show
export NAS_LAN_IFACE := vmbr0
export NAS_SSH_PORT := 22

# 5. HUB01 constants
HUB01_ADDR := 10.89.12.11
HUB01_LAN_IFACE := ens3 # ip route get 10.89.12.1 | awk '/dev/ {print $5}'

export SSH_PORT_AC86U := 2222
# ============================================================================
# ACME Configuration (Option C: FHS-compliant, system-level)
# ============================================================================

# Homelab domain (canonical identity)
DOMAIN               := bardi.ch
export DOMAIN
RENEW_THRESHOLD_DAYS := 30
export APT_CNAME_EXPECTED   := bardi.ch

# ------------------------------------------------------------
# ACME binary (operator-installed)
# ------------------------------------------------------------
ACME_BIN := /usr/local/bin/acme.sh
export ACME_BIN
# ------------------------------------------------------------
# ACME state (root-owned, system-level), used by depoy scripts
# ------------------------------------------------------------
ACME_HOME := /var/lib/acme
export ACME_HOME

# ------------------------------------------------------------
# Canonical TLS store, used by dnsdist, traefik, homepage, router, etc.
# ------------------------------------------------------------
TLS_CANONICAL := /var/lib/ssl/canonical
export TLS_CANONICAL

# ------------------------------------------------------------
# DDNS environment file (root-owned), used in mk/07_secrets.mk
# ------------------------------------------------------------
DDNS_ENV_FILE := /etc/homelab/ddns.env
export DDNS_ENV_FILE

# Canonical certificate store
SSL_CANONICAL_DIR := /var/lib/ssl/canonical

# ------------------------------------------------------------
# ACME systemd units, used in mk/40_acme.mk
# ------------------------------------------------------------
ACME_SERVICE_FILE := /etc/systemd/system/acme-renew.service
ACME_TIMER_FILE   := /etc/systemd/system/acme-renew.timer
export ACME_SERVICE_FILE
export ACME_TIMER_FILE

# ECC certificates (acme.sh output: cert.pem, fullchain.pem, privkey.pem)
SSL_CERT_ECC  := $(ACME_HOME)/$(DOMAIN)_ecc/cert.pem
SSL_CHAIN_ECC := $(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem
SSL_KEY_ECC   := $(ACME_HOME)/$(DOMAIN)_ecc/privkey.pem

# Deployment targets
SSL_DEPLOY_DIR_CADDY     := /etc/ssl/caddy
SSL_DEPLOY_DIR_HEADSCALE := /etc/ssl/headscale

# Unbound
UNBOUND_PORT := 15335

# Role
ROLE := service

# ----------------------------------------------------------------------------
# 4. State / Stamp Directory Configuration
# ----------------------------------------------------------------------------

# Ensure HOME is always set inside Make (sudo sometimes clears it)
HOME ?= $(shell echo $$HOME)

# User-level stamp directory
STAMP_DIR_USER := $(HOME)/.local/state/homelab
export STAMP_DIR_USER

# System-wide stamp directory (never mixed with user stamps)
STAMP_DIR_ROOT := /tank/julie/src/homelab/.state/stamps
export STAMP_DIR_ROOT

# Canonical marker path
export ROUTER_PREFIX_MARKER := $(STAMP_DIR_ROOT)/router-prefix.changed

$(ROUTER_PREFIX_MARKER): ensure-state-dirs

# Deterministic PATH for all recipes
PATH := /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# Packages UGOS ships and cannot be removed
UGOS_VENDOR_PACKAGES := \
	curl jq git nftables iptables unbound unbound-anchor dnsutils dnsperf \
	iperf3 ripgrep htop libc-ares-dev python3-venv \
	netfilter-persistent iptables-persistent \
	ethtool tcpdump ndisc6

# Packages we actually install and can uninstall
APT_INSTALLABLE_PACKAGES := \
	build-essential shellcheck pup codespell aspell aspell-en ndppd \
	knot-dnsutils apt-cacher-ng unzip git-filter-repo rclone \
	wireguard-tools qrencode

# ----------------------------------------------------------------------------
# SSH Configuration (authoritative, non-secret)
# ----------------------------------------------------------------------------
# These variables define the canonical SSH parameters used by the homelab
# when generating ~/.ssh/config via the Makefile template.
#
# - SSH_IDENTITY_FILE: Deterministic identity path resolved via ACTUAL_HOME.
# - SSH_STRICT: StrictHostKeyChecking policy. "accept-new" ensures automation
#               survives router/NAS key regeneration events.
# - SSH_PORT_ROUTER: Router SSH port (Merlin always uses 2222).
# - SSH_PORT_DEFAULT: Default SSH port for all other LAN hosts.
#
# These variables are intentionally minimal. All host IPs and SSH users are
# already defined above (LAN_* and SSH_USER_*), so the SSH template can be
# rendered without introducing redundant or duplicated configuration.
#
# This block is safe to commit and contains no secrets.
# ----------------------------------------------------------------------------

export SSH_IDENTITY_FILE := $(ACTUAL_HOME)/.ssh/id_ed25519
export SSH_STRICT := accept-new

export SSH_PORT_ROUTER := $(ROUTER_SSH_PORT)
export SSH_PORT_DEFAULT := 22

# System‑Level nftables Configuration
export HOMELAB_NFT_ETC_DIR       := /etc/nftables
export HOMELAB_NFT_RULESET       := $(HOMELAB_NFT_ETC_DIR)/homelab.nft
export HOMELAB_NFT_HASH_FILE     := $(STAMP_DIR_ROOT)/nftables.applied.sha256
export HOMELAB_NFT_ROLLBACK_FLAG := "/run/homelab-nft.pending"

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
	10.89.12.4:22

# ----------------------------------------------------------------------------
# 1. some constants
# ----------------------------------------------------------------------------
HEADSCALE_USER := headscale
HEADSCALE_GROUP := headscale

# ----------------------------------------------------------------------------
# 2. Global Security Policy (Admins, Groups, Service Accounts)
# ----------------------------------------------------------------------------

# Human operators allowed to mutate system state
AUTHORIZED_ADMINS := julie leona

# Human-admin groups (must exist; enforced by mk/10_groups.mk)
ADMIN_GROUPS := admins docker

# Service-owned groups (no human membership)
SERVICE_GROUPS := headscale _dnsdist ssl-cert dnswarm dnscrypt

# Service accounts (user:primary_group)
SERVICE_MAP := \
	$(HEADSCALE_USER):$(HEADSCALE_GROUP) \
	_dnsdist:_dnsdist \
	dnswarm:dnswarm

# ----------------------------------------------------------------------------
# 3. Root Ownership Defaults
# ----------------------------------------------------------------------------

# --- ROOT identity (1 syscall) ---
ROOT_PASSWD := $(shell getent passwd root 2>/dev/null || echo "root:x:0:0:root:/root:/bin/sh")
ROOT_UID    := $(word 3,$(subst :, ,$(ROOT_PASSWD)))
ROOT_GID    := $(word 4,$(subst :, ,$(ROOT_PASSWD)))
ROOT_HOME   := $(word 6,$(subst :, ,$(ROOT_PASSWD)))

# --- USER identity (1 syscall), also called OPERATOR ---
USER_PASSWD := $(shell uid=$$(id -u); gid=$$(id -g); \
	getent passwd $$uid 2>/dev/null || echo "user:x:$$uid:$$gid:user:$$HOME:/bin/sh")
USER_UID    := $(word 3,$(subst :, ,$(USER_PASSWD)))
USER_GID    := $(word 4,$(subst :, ,$(USER_PASSWD)))
USER_HOME   := $(word 6,$(subst :, ,$(USER_PASSWD)))
USER        := $(word 1,$(subst :, ,$(USER_PASSWD)))

# ----------------------------------------------------------------------------
# 5. Documentation Directory (Deferred assignment)
# ----------------------------------------------------------------------------
DOCS_DIR = $(INSTALL_PATH)/docs

# ----------------------------------------------------------------------------
# 6. Tooling Definitions (Blueprints vs. Artifacts)
# ----------------------------------------------------------------------------

# BLUEPRINTS — always present in the Git repo
RUN_ROOT_SRC      := $(REPO_ROOT)/scripts/run-as-root.sh
# IFC v3 — portable, zero-bootstrap (blueprints only; may be used in-place or installed)
IFC_V3_SINGLE_SRC := $(REPO_ROOT)/scripts/install_file_if_changed_v3.sh
IFC_V3_PLURAL_SRC := $(REPO_ROOT)/scripts/install_files_if_changed_v3.sh

IFC_URL_SRC       := $(REPO_ROOT)/scripts/install_url_file_if_changed.sh
COMMON_SRC        := $(REPO_ROOT)/scripts/common.sh

# ARTIFACTS — installed system locations
export run_as_root                 := $(INSTALL_SBIN_PATH)/run-as-root.sh
export INSTALL_FILE_IF_CHANGED     := $(INSTALL_PATH)/install_file_if_changed_v3.sh
export INSTALL_FILES_IF_CHANGED    := $(INSTALL_PATH)/install_files_if_changed_v3.sh

export INSTALL_URL_FILE_IF_CHANGED := $(INSTALL_PATH)/install_url_file_if_changed.sh

# ----------------------------------------------------------------------------
# 7. Build Invariants
# ----------------------------------------------------------------------------
N_WORKERS := $(shell nproc | awk '{print ($$1 > 1 ? $$1 - 1 : 1)}')
INSTALL_IF_CHANGED_EXIT_CHANGED ?= 3
INSTALL_IF_CHANGED_EXIT_UNCHANGED := 0
INSTALL_IF_CHANGED_EXIT_ERROR := 1

# ----------------------------------------------------------------------------
# 8. Router Mappings (Non-secret)
# ----------------------------------------------------------------------------
SRC_SCRIPTS          := $(REPO_ROOT)/router/jffs/scripts
ROUTER_CADDYFILE_SRC := $(REPO_ROOT)/router/caddy/Caddyfile
ROUTER_CADDYFILE_DST := /jffs/caddy/Caddyfile

# Router-side WireGuard firewall script (non-secret, generated)
ROUTER_WG_FIREWALL_DST := /jffs/scripts/wg-firewall.sh

ROUTER_CADDY_VERSION ?= 2.11.2
ROUTER_CADDY_ARCH    ?= linux_arm64
ROUTER_CADDY_URL     := https://github.com/caddyserver/caddy/releases/download/v$(ROUTER_CADDY_VERSION)/caddy_$(ROUTER_CADDY_VERSION)_$(ROUTER_CADDY_ARCH).tar.gz
ROUTER_CADDY_BIN     := /tmp/mnt/sda/router/bin/caddy
ROUTER_CADDY_STAMP   := /jffs/.stamps/caddy.installed
ROUTER_CADDY_SHA256  := b9d88bec4254d0a98bd415ad60f97f37e4222dec96235c00b442437f5e303a32

COMMON_SH_DST        := $(ROUTER_SCRIPTS)/common.sh

CERTS_CREATE       := $(ROUTER_SCRIPTS)/certs-create.sh
CERTS_DEPLOY       := $(INSTALL_PATH)/deploy_certificates.sh
GEN_CLIENT_CERT    := $(ROUTER_SCRIPTS)/generate-client-cert.sh
GEN_CLIENT_WRAPPER := $(ROUTER_SCRIPTS)/gen-client-cert-wrapper.sh

# ----------------------------------------------------------------------------
# 9. Security & Identity (Public key only — no secrets)
# This is the canonical expected Age public key. All homelab secrets are
# encrypted with this identity. If you rotate the Age key, you MUST update
# this value and re-encrypt all SOPS-managed secrets stored in KeePass.
# ----------------------------------------------------------------------------
SOPS_AGE_PUBKEY_EXPECTED := age1rzyyxnn2ejkchp4jewdpw92av689wdtj2kgrv3ys4p3chn862vjqc3fs5n

# ----------------------------------------------------------------------------
# 10. SSH Configuration for Router (Non-secret)
# ----------------------------------------------------------------------------
SSH_OPTS   := -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes

# ----------------------------------------------------------------------------
# 11. Local Tooling Policy (Declarative Only)
# ----------------------------------------------------------------------------
# These values are consumed by mk/10_local-tools.mk (logic module).
# No logic or mutation belongs here — only policy.

# yq GitHub repository and asset
YQ_GITHUB_REPO := mikefarah/yq
YQ_ASSET       := yq_linux_amd64
YQ_STAMP := $(STAMP_DIR_ROOT)/yq.installed

YQ := /usr/local/bin/yq
export YQ

# yq version policy:
#   - Set to a pinned version (e.g. v4.53.2)
#   - Or set to latest to always track upstream, e.g. env YQ_VERSION=latest make install-yq
YQ_VERSION ?= v4.53.6

YQ_URL := https://github.com/$(YQ_GITHUB_REPO)/releases/download/$(YQ_VERSION)/$(YQ_ASSET)

# Expected SHA256 for pinned version (ignored when using latest)
YQ_SHA256 ?= sha256:c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385

ULA_PREFIX_NVRAM = $(ula_prefix_nvram)

# Nas address (from config.mk)
NAS_LAN_IP = $(LAN_NAS)
NAS_LAN_IP6 = $(LAN6_NAS)

# Construct full SSH host (derived, not exported)
ROUTER_HOST = $(SSH_USER_ROUTER)@$(ROUTER_ADDR)

# ----------------------------------------------------------------------------
# Runtime directory and files (RAM-only, for user)
# ----------------------------------------------------------------------------
#export RUNTIME_DIR := /run/user/$(USER_UID)/homelab/
export RUNTIME_DIR := $(STAMP_DIR_USER)/runtime

TMP_DDNS_CONF := $(RUNTIME_DIR)/.ddns_confidential_$$PPID

TMP_DNSMASQ_ADD := $(RUNTIME_DIR)/.dnsmasq_conf_add_$$PPID
TMP_DNSMASQ_HOSTS := $(RUNTIME_DIR)/.dnsmasq_hosts_add_$$PPID

TMP_ROUTER_WG_FIREWALL := $(RUNTIME_DIR)/.wg_firewall_$$PPID

TMP_ROUTER_ULA := $(RUNTIME_DIR)/router_ula_$$PPID

# $(file …) bypasses the shell, so $PPID never expands and the NAT script path must not depend on it
TMP_ROUTER_NAT := $(RUNTIME_DIR)/.router_nat

export WG_PLAN_SUBNETS := $(INSTALL_PATH)/wg-plan-subnets.sh

# ------------------------------------------------------------
# Homelab Age Identity (SOPS)
# Secrets are NEVER loaded into Make variables.
# Secrets are injected ONLY inside a single shell via sops exec-env.
# ------------------------------------------------------------

# Ensure SOPS can decrypt inside Make recipes
SOPS_AGE_KEY_FILE := /etc/sops/keys/age.key
export SOPS_AGE_KEY_FILE

SECRETS_FILE := $(REPO_ROOT)/secrets.enc.yaml
export SECRETS_FILE

SOPS_AGE_KEY_DIR := $(dir $(SOPS_AGE_KEY_FILE))

SOPS_BIN := $(INSTALL_PATH)/sops
export SOPS_BIN

SYSCTL_BIN := $(shell command -v sysctl)

SYSCTL_SRC := $(REPO_ROOT)/config/sysctl.d/99-homelab-forwarding.conf.in
SYSCTL_DST := /etc/sysctl.d/99-homelab-forwarding.conf

# ============================================================
# ACME systemd units + scripts
# ============================================================

ACME_ISSUE_SERVICE := /etc/systemd/system/acme-issue.service
export ACME_ISSUE_SERVICE

ACME_ISSUE_TIMER := /etc/systemd/system/acme-issue.timer
export ACME_ISSUE_TIMER

ACME_RENEW_SERVICE := /etc/systemd/system/acme-renew.service
export ACME_RENEW_SERVICE

ACME_RENEW_TIMER := /etc/systemd/system/acme-renew.timer
export ACME_RENEW_TIMER

ACME_ISSUE_SCRIPT := /usr/local/bin/acme-issue.sh
export ACME_ISSUE_SCRIPT

ACME_RENEW_SCRIPT := /usr/local/bin/acme-renew.sh
export ACME_RENEW_SCRIPT

# Out-of-repo absolute path for topology isolation of Wireguard input
WG_INPUT_DIR := $(WG_ROOT)/input
WG_INTERFACES_TSV := $(WG_INPUT_DIR)/wg-interfaces.tsv

USE_TAILSCALED := 0

define INSTALL_FILE_NORMALIZED
	rc=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
		"$(1)" "$(2)" "$(3)" \
		"$(4)" "$(5)" "$(6)" \
		"$(7)" "$(8)" "$(9)" \
		|| rc=$$?; \
	case "$$rc" in \
		$(INSTALL_IF_CHANGED_EXIT_UNCHANGED)|$(INSTALL_IF_CHANGED_EXIT_CHANGED)|'') exit 0 ;; \
		*[!0-9]* ) exit 0 ;; \
		*) exit "$$rc" ;; \
	esac
endef

define GENERATE_AND_INSTALL_FILE
	tmp="$$(mktemp)"; \
	$(file >$$tmp,$(value $(1))) \
	newhash="$$(sha256sum "$$tmp" | awk '{print $$1}')"; \
	\
	# compute path identity hash (no salt)
	path="$(2)"; \
	key_hash="$$(printf '%s' "$$path" | sha256sum | awk '{print $$1}')"; \
	dir1="$${key_hash:0:2}"; \
	dir2="$${key_hash:2:5}"; \
	meta="$(STAMP_DIR_ROOT)/$$dir1/$$dir2/$$key_hash"; \
	\
	# read old hash from sharded metadata file (if any)
	if [ -f "$$meta" ]; then \
		oldhash="$$(cat "$$meta")"; \
	else \
		oldhash=""; \
	fi; \
	\
	# fast path: content unchanged, skip IFC_v3
	if [ "$$newhash" = "$$oldhash" ]; then \
		rm -f "$$tmp"; \
		echo "🟢 already up-to-date: $(2)"; \
		exit 0; \
	fi; \
	\
	# slow path: install via IFC_v3
	rc=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
		"" "" "$$tmp" \
		"" "" "$(2)" \
		"$(ROOT_UID)" "$(ROOT_GID)" "$(3)" \
		|| rc=$$?; \
	\
	# update sharded metadata file with new content hash
	mkdir -p "$(STAMP_DIR_ROOT)/$$dir1/$$dir2"; \
	echo "$$newhash" > "$$meta"; \
	rm -f "$$tmp"; \
	\
	# normalize IFC_v3 return code
	case "$$rc" in \
		0|3|'') exit 0 ;; \
		*[!0-9]* ) exit 0 ;; \
		*) exit "$$rc" ;; \
	esac
endef

.PHONY: homelab-env
homelab-env: $(BOOTSTRAP_CORE) $(run_as_root)
	@tmp="$$(mktemp)"; \
	printf "%s\n" "# Canonical Network Environment (DO NOT EDIT, generated by homelab-env)" > "$$tmp"; \
	printf "%s\n" "HOMELAB_ROOT=\"$(HOMELAB_DIR)\"" >> "$$tmp"; \
	printf "%s\n" "LAN6_PREFIX_BASE=\"$(LAN6_PREFIX_BASE)\"" >> "$$tmp"; \
	printf "%s\n" "# Required by mk/config.mk" >> "$$tmp"; \
	printf "%s\n" "ACME_HOME=\"$(ACME_HOME)\"" >> "$$tmp"; \
	printf "%s\n" "# Required by IFC v3" >> "$$tmp"; \
	printf "%s\n" "INSTALL_PATH=\"$(INSTALL_PATH)\"" >> "$$tmp"; \
	printf "%s\n" "INSTALL_SBIN_PATH=\"$(INSTALL_SBIN_PATH)\"" >> "$$tmp"; \
	printf "%s\n" "# Required by graph.mk (WireGuard plan)" >> "$$tmp"; \
	printf "%s\n" "WG_PLAN_SUBNETS=\"$(WG_PLAN_SUBNETS)\"" >> "$$tmp"; \
	$(run_as_root) chmod 640 "$$tmp"; \
	rc=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
		"" "" "$$tmp" \
		"" "" "$(HOMELAB_DIR)/config/homelab.env" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0640" \
		|| rc=$$?; \
	rm -f "$$tmp"; \
	case "$$rc" in \
		0|3|'') exit 0 ;; \
		*[!0-9]* ) exit 0 ;; \
		*) exit "$$rc" ;; \
	esac

.PHONY: homelab-prefix-env
homelab-prefix-env: $(BOOTSTRAP_CORE) $(run_as_root)
	@tmp="$$(mktemp)"; \
	printf "%s\n" "# Canonical Prefix Environment (DO NOT EDIT, generated by homelab-prefix-env)" > "$$tmp"; \
	printf "%s\n" "HOMELAB_ROOT=\"$(HOMELAB_DIR)\"" >> "$$tmp"; \
	printf "%s\n" "ULA_BASE=\"$(LAN6_PREFIX_BASE)\"" >> "$$tmp"; \
	printf "%s\n" "NAS_LAN_IFACE=\"$(NAS_LAN_IFACE)\"" >> "$$tmp"; \
	printf "%s\n" "STAMP_DIR_ROOT=\"$(STAMP_DIR_ROOT)\"" >> "$$tmp"; \
	$(run_as_root) chmod 640 "$$tmp"; \
	rc=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
		"" "" "$$tmp" \
		"" "" "/etc/homelab/homelab-prefix.env" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0640" \
		|| rc=$$?; \
	rm -f "$$tmp"; \
	case "$$rc" in \
		0|3|'') exit 0 ;; \
		*[!0-9]* ) exit 0 ;; \
		*) exit "$$rc" ;; \
	esac

/etc/homelab/homelab-prefix.env: homelab-prefix-env
