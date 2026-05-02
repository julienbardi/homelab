# config.mk — committed, non-secret configuration

# Paths
HOMELAB_DIR := /volume1/homelab
WG_ROOT     := $(HOMELAB_DIR)/wireguard
STAMP_DIR   := /var/lib/homelab

# System
SYSTEMD_DIR       := /etc/systemd/system
INSTALL_PATH      := /usr/local/bin
INSTALL_SBIN_PATH := /usr/local/sbin

# Network - General
PUBLIC_DNS := 1.1.1.1
LAN_IFACE  := eth0

# Certificates & Identity
DOMAIN               := bardi.ch
ACME_HOME            := /var/lib/acme
RENEW_THRESHOLD_DAYS := 30
APT_CNAME_EXPECTED   := bardi.ch

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
export ROUTER_SCRIPTS   := /jffs/scripts
ROUTER_WG_DIR    := /jffs/etc/wireguard
ROUTER_CADDY_BIN := /tmp/mnt/sda/router/bin/caddy
ROUTER_CADDY_STAMP := /jffs/.stamps/caddy.stamp

# Tooling Metadata
export ROUTER_SCRIPTS_OWNER := 0
export ROUTER_SCRIPTS_GROUP := 0
export ROUTER_SCRIPTS_MODE  := 0755

# Unbound
UNBOUND_PORT := 5335

# Role
ROLE := service
