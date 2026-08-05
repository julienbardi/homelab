# mk/prereqs-knot.mk — Knot DNS repo + kdig installation
# ------------------------------------------------------------
# CONTRACT:
# - repo install is idempotent
# - kdig installation is deterministic
# - failures are explicit
# ------------------------------------------------------------

# Knot DNS repository (Bookworm for Proxmox 8)
KNOT_REPO_LIST := /etc/apt/sources.list.d/knot-dns.list
KNOT_REPO_URL  := https://deb.knot-dns.cz/knot-dns
KNOT_GPG_URL   := https://deb.knot-dns.cz/knot-dns.gpg

.PHONY: install-knot-repo install-kdig

install-knot-repo:
	@$(run_as_root) sh -eu -c '\
		echo "deb $(KNOT_REPO_URL) bookworm main" > "$(KNOT_REPO_LIST)"; \
		curl -fsSL "$(KNOT_GPG_URL)" | apt-key add -; \
		apt update; \
	'

install-kdig: install-knot-repo
	@$(call apt_install,kdig,knot-dnsutils) || \
		echo "⚠️ kdig not installable; curl fallback enabled"
