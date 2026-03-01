# ============================================================
# mk/40_router.mk — Router orchestration
# ============================================================
# --------------------------------------------------------------------
# CONTRACT:
# - Router is treated as a remote execution surface
# - All mutations go through router-sync-scripts.sh
# - Script installation is handled by the global install pattern
# - Operator must be present (interactive gate)
# - Executed by /bin/sh
# - Escape $ -> $$ (Make expands $ first)
# --------------------------------------------------------------------

# Installed execution surface (authoritative)
ROUTER_SYNC_SCRIPT := $(INSTALL_PATH)/router-sync-scripts.sh
ROUTER_INSTALL_CA_SCRIPT := $(INSTALL_PATH)/router-install-ca.sh
# --------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------

.PHONY: router-ssh-ready git-clean router-sync-scripts
.PHONY: install-router-ca router-publish-ca
.PHONY: router-ssh-prereqs
router-ssh-prereqs: prereqs-root-ssh-key prereqs-operator-ssh-key

# Explicit SSH reachability check (no mutation)
router-ssh-ready: router-ssh-prereqs
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) true

git-clean:
	@git diff --quiet || { echo "❌ Working tree not clean"; exit 1; }

# --------------------------------------------------------------------
# Primary router orchestration
# --------------------------------------------------------------------

router-sync-scripts: prereqs-run-as-root $(ROUTER_SYNC_SCRIPT) install-router-ca router-ssh-ready git-clean
	@ROUTER_HOST="$(ROUTER_HOST)" ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" HOMELAB_DIR="$(MAKEFILE_DIR)" $(ROUTER_SYNC_SCRIPT)

install-router-ca: ensure-run-as-root router-ssh-prereqs
	@$(run_as_root) install -o root -g root -m 0755 \
		$(MAKEFILE_DIR)scripts/router-install-ca.sh \
		$(ROUTER_INSTALL_CA_SCRIPT)

router-publish-ca: router-sync-scripts
	@true

REQUIRED_PKGS := coreutils-timeout openssh-client coreutils iperf3 htop

.PHONY: install-router-tools
install-router-tools: router-ssh-prereqs
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
mkdir -p /jffs/sentinels && chmod 700 /jffs/sentinels; \
SENTINEL="/jffs/sentinels/opkg_update"; \
MAX_AGE=$$((24*3600)); \
now=$$(date +%s); \
last_update=0; \
[ -f "$$SENTINEL" ] && last_update=$$(cat "$$SENTINEL" 2>/dev/null || echo 0); \
age=$$(( now - last_update )); \
if [ "$$age" -gt "$$MAX_AGE" ]; then \
	opkg update && echo "$$now" > "$$SENTINEL" && chmod 600 "$$SENTINEL" || exit 2; \
fi; \
opkg install $(REQUIRED_PKGS) || exit 3; \
'
	@status=$$?; \
	if [ $$status -eq 0 ]; then \
		echo "✅ Required tools installed or already present on router $(ROUTER_HOST):$(ROUTER_SSH_PORT)"; \
	elif [ $$status -eq 2 ]; then \
		echo "❌ Failed to perform opkg update on router $(ROUTER_HOST):$(ROUTER_SSH_PORT)"; \
	elif [ $$status -eq 3 ]; then \
		echo "❌ Failed to install required packages on router $(ROUTER_HOST):$(ROUTER_SSH_PORT)"; \
	else \
		echo "❌ Unknown error (exit $$status) on router $(ROUTER_HOST):$(ROUTER_SSH_PORT)"; \
	fi
