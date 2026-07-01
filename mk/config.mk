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
export LAN6_NET      := fd89:7a3b:42c0::/64
export LAN6_ROUTER   := fd89:7a3b:42c0::1
export LAN6_SYNOLOGY := fd89:7a3b:42c0::2
export LAN6_NAS      := fd89:7a3b:42c0::4
export LAN6_AC86U    := fd89:7a3b:42c0::6

export LAN6_PREFIXLEN := 64
# Add others as needed:
# export LAN6_QNAP     := ...

# WireGuard DNS topology (authoritative, non-secret)
# Fastest-first ordering: DoH → Router IPv4 → NAS IPv6
export WG_DOH_IPV4       := $(LAN_NAS):8053
export WG_DOH_IPV6       := $(LAN6_NAS):8053
export WG_DNS_ROUTER_IPV4 := $(LAN_ROUTER)
export WG_DNS_NAS_IPV6    := $(LAN6_NAS)

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
HOMELAB_DIR := /volume1/homelab
WG_ROOT     := $(HOMELAB_DIR)/wireguard

# System
SYSTEMD_DIR       := /etc/systemd/system
INSTALL_PATH      := /usr/local/bin
INSTALL_SBIN_PATH := /usr/local/sbin

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
export ROUTER_LAN_IFACE  := eth0

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

# 3. QNAP constants
QNAP_LAN_IFACE := eth0

# 4. NAS constants
NAS_LAN_IFACE := eth0

# 5. HUB01 constants
HUB01_ADDR := 10.89.12.11
HUB01_LAN_IFACE := ens3 # ip route get 10.89.12.1 | awk '/dev/ {print $5}'

# Certificates & Identity
DOMAIN               := bardi.ch
ACME_HOME := $(shell . /volume1/homelab/homelab.env && echo $$ACME_HOME)
RENEW_THRESHOLD_DAYS := 30
export APT_CNAME_EXPECTED   := bardi.ch

# Canonical certificate store
SSL_CANONICAL_DIR := /var/lib/ssl/canonical

# ECC certificates (preferred)
SSL_CERT_ECC  := $(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).cer
SSL_CHAIN_ECC := $(ACME_HOME)/$(DOMAIN)_ecc/fullchain.cer
SSL_KEY_ECC   := $(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).key

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
XDG_STATE_HOME := $(HOME)/.local/state
STAMP_DIR_USER := $(XDG_STATE_HOME)/homelab
STAMP_DIR_ROOT := /var/lib/homelab

# Canonical marker path
export ROUTER_PREFIX_MARKER := $(STAMP_DIR_ROOT)/router-prefix.changed

$(ROUTER_PREFIX_MARKER): | $(STAMP_DIR_ROOT)

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
