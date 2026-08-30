# mk/prereqs-variables.mk
# ------------------------------------------------------------
# Variables, paths, package lists, repo URLs
# ------------------------------------------------------------

PREREQS_PACKAGES := \
	apt-cacher-ng \
	aspell \
	aspell-en \
	ethtool \
	ndppd \
	wireguard-tools \
	unzip \
	libc-ares-dev \
	qrencode \
	ldnsutils \
	coreutils util-linux

PREREQS_SOURCES := \
	mk/00_prereqs.mk \
	mk/20_deps.mk \
	mk/71_dns-warm.mk

TAILSCALE_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TAILSCALE_KEY_URL := https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg
TAILSCALE_REPO_FILE := /etc/apt/sources.list.d/tailscale.list
TAILSCALE_REPO_LINE := deb [signed-by=$(TAILSCALE_KEYRING)] https://pkgs.tailscale.com/stable/debian bookworm main

PYTHON_MIN ?= 3.11.2
