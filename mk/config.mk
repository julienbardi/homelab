# config.mk — committed, non-secret configuration

# LAN Topology (authoritative)
export LAN_NET      := 10.89.12.0/24
export LAN_NET_ADDR := 10.89.12.0
export LAN_ROUTER   := 10.89.12.1
export LAN_SYNOLOGY := 10.89.12.2
export LAN_QNAP     := 10.89.12.3
export LAN_NAS      := 10.89.12.4
export LAN_AC86U    := 10.89.12.6

# IPv6 ULA Topology (authoritative)
export LAN6_NET      := fd89:7a3b:42c0::/64
export LAN6_ROUTER   := fd89:7a3b:42c0::1
export LAN6_SYNOLOGY := fd89:7a3b:42c0::2
export LAN6_NAS      := fd89:7a3b:42c0::4
export LAN6_AC86U    := fd89:7a3b:42c0::6

export LAN6_PREFIXLEN := 64
# Add others as needed:
# export LAN6_QNAP     := ...

# SSH users per host
export SSH_USER_ROUTER   := julie
export SSH_USER_NAS      := julie
export SSH_USER_SYNOLOGY := julie
export SSH_USER_QNAP     := admin
export SSH_USER_AC86U    := admin

# Bind ROUTER_USER for dns-suite
export ROUTER_USER := $(SSH_USER_ROUTER)

# Paths
HOMELAB_DIR := /volume1/homelab
WG_ROOT     := $(HOMELAB_DIR)/wireguard
STAMP_DIR   := /var/lib/homelab

# System
SYSTEMD_DIR       := /etc/systemd/system
INSTALL_PATH      := /usr/local/bin
INSTALL_SBIN_PATH := /usr/local/sbin

# Network - General
export PUBLIC_DNS := 1.1.1.1
LAN_IFACE  := eth0

# ------------------------------------------------------------
# Topology constants (raw inputs — NEVER exported)
# ------------------------------------------------------------
router_addr      := 10.89.12.1
router_ssh_port  := 2222

# Ensure these lowercase variables NEVER leak into the environment
unexport router_addr
unexport router_ssh_port

# ------------------------------------------------------------
# Exported, Make-safe constants (uppercase — ALWAYS exported)
# ------------------------------------------------------------
export ROUTER_ADDR      := $(router_addr)
export ROUTER_SSH_PORT  := $(router_ssh_port)

export ula_prefix_nvram := fd89:7a3b:42c0::/48
export router_ula_ip6   := fd89:7a3b:42c0::1

# Certificates & Identity
DOMAIN               := bardi.ch
ACME_HOME            := /var/lib/acme
RENEW_THRESHOLD_DAYS := 30
export APT_CNAME_EXPECTED   := bardi.ch

# Canonical certificate store
SSL_CANONICAL_DIR := /var/lib/ssl/canonical

# ECC certificates (preferred)
SSL_CERT_ECC  := $(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).cer
SSL_CHAIN_ECC := $(ACME_HOME)/$(DOMAIN)_ecc/fullchain.cer
SSL_KEY_ECC   := $(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).key

# RSA certificates (fallback)
SSL_CERT_RSA  := $(ACME_HOME)/$(DOMAIN)/$(DOMAIN).cer
SSL_CHAIN_RSA := $(ACME_HOME)/$(DOMAIN)/fullchain.cer
SSL_KEY_RSA   := $(ACME_HOME)/$(DOMAIN)/$(DOMAIN).key

# Deployment targets
SSL_DEPLOY_DIR_CADDY     := /etc/ssl/caddy
SSL_DEPLOY_DIR_HEADSCALE := /etc/ssl/headscale

# Router specific paths
export ROUTER_SCRIPTS    := /jffs/scripts
ROUTER_WG_DIR            := /jffs/configs
ROUTER_CADDY_BIN         := /tmp/mnt/sda/router/bin/caddy
ROUTER_CADDY_STAMP       := /jffs/.stamps/caddy.stamp

# Tooling Metadata
ROUTER_SCRIPTS_OWNER := 0
ROUTER_SCRIPTS_GROUP := 0
ROUTER_SCRIPTS_MODE  := 0755

# Unbound
UNBOUND_PORT := 15335

# Role
ROLE := service

# Canonical marker path
export SYSTEM_STATE_DIR := /var/lib/homelab
export ROUTER_PREFIX_MARKER := $(SYSTEM_STATE_DIR)/router-prefix.changed

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
# 12. DHCP Architecture (Declarative Policy)
# ----------------------------------------------------------------------------
# Static DHCP reservations: .2 – .99
# Dynamic DHCP pool:        .100 – .254
DHCP_STATIC_MAX    := 99
LAN_PREFIX        := 10.89.12
DHCP_DYNAMIC_START := $(LAN_PREFIX).100
DHCP_DYNAMIC_END   := $(LAN_PREFIX).254
