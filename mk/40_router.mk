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

# --------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------

.PHONY: router-ssh-ready git-clean router-sync-scripts

# Explicit SSH reachability check (no mutation)
router-ssh-ready:
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) true

git-clean:
	@git diff --quiet || { echo "❌ Working tree not clean"; exit 1; }

# --------------------------------------------------------------------
# Primary router orchestration
# --------------------------------------------------------------------

router-sync-scripts: $(ROUTER_SYNC_SCRIPT) router-ssh-ready git-clean
	@$(ROUTER_SYNC_SCRIPT)
