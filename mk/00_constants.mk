# mk/00_constants.mk
# Canonical Make constants (build-time)

PUBLIC_DNS := 1.1.1.1
SYSTEMD_DIR := /etc/systemd/system
INSTALL_PATH := /usr/local/bin
INSTALL_SBIN_PATH := /usr/local/sbin
STAMP_DIR := /var/lib/homelab

# Host responsibility (router | service | client)
ROLE := service

APT_CNAME_EXPECTED := bardi.ch

HOMELAB_ROOT := /volume1/homelab
WG_ROOT := $(HOMELAB_ROOT)/wireguard
DOCS_DIR := $(HOMELAB_ROOT)/docs
SECURITY_DIR := $(HOMELAB_ROOT)/security

# Export global paths for all scripts
export WG_ROOT
export SECURITY_DIR
export HOMELAB_ROOT