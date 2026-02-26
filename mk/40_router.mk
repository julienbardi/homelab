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
# - Escape $ → $$ (Make expands $ first)
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

router-sync-scripts: prereqs-run-as-root $(ROUTER_SYNC_SCRIPT) router-ssh-ready git-clean
	@HOMELAB_DIR=$(MAKEFILE_DIR) $(ROUTER_SYNC_SCRIPT)

install-router-ca: ensure-run-as-root router-ssh-prereqs
	@$(run_as_root) install -o root -g root -m 0755 \
		$(MAKEFILE_DIR)scripts/router-install-ca.sh \
		$(ROUTER_INSTALL_CA_SCRIPT)

router-publish-ca: router-sync-scripts
	@true
