# mk/00_constants.mk
# Canonical Make constants (build-time)

NAS_LAN_IP := 10.89.12.4
NAS_LAN_IP6 := fd89:7a3b:42c0::4

ROUTER_LAN_IP := 10.89.12.1

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

VERBOSE ?= 0

# Export global paths for all scripts
export WG_ROOT
export SECURITY_DIR
export HOMELAB_ROOT