# ============================================================
# mk/20_gitignore.mk — externalized invariants
# ============================================================

STAMPS_SCRIPT          := $(INSTALL_PATH)/stamps.sh
GITIGNORE_CHECK_SCRIPT := $(INSTALL_PATH)/gitignore-check.sh
GITIGNORE_STAMP_SCRIPT := $(INSTALL_PATH)/gitignore-stamp.sh
SECRETS_STAMP_SCRIPT   := $(INSTALL_PATH)/secrets-stamp.sh
LAN_IP_CHECK_SCRIPT    := $(INSTALL_PATH)/detect-unauthorized-lan-ips.sh
SECRETS_CHECK_SCRIPT   := $(INSTALL_PATH)/secrets-check.sh

RUNTIME_SCRIPTS := \
	$(STAMPS_SCRIPT) \
	$(GITIGNORE_CHECK_SCRIPT) \
	$(GITIGNORE_STAMP_SCRIPT) \
	$(SECRETS_STAMP_SCRIPT) \
	$(LAN_IP_CHECK_SCRIPT) \
	$(SECRETS_CHECK_SCRIPT)

# ------------------------------------------------------------
# Lint target
# ------------------------------------------------------------
.PHONY: lint-gitignore
lint-gitignore: $(GITIGNORE_CHECK_SCRIPT)
	@REPO_ROOT="$(REPO_ROOT)" bash $(GITIGNORE_CHECK_SCRIPT)

# ------------------------------------------------------------
# Repo-preflight (Optimized with conditional heavy scan & parallel checks)
# ------------------------------------------------------------
.PHONY: repo-preflight
repo-preflight: $(RUNTIME_SCRIPTS)
	@echo "🚨 Running repo-preflight..."
	@rc_secrets=0; rc_git=0; rc_sec_stamp=0; rc_lan=0; \
	\
	# Only run heavy secret scan if secrets stamp indicates changes \
	( REPO_ROOT="$(REPO_ROOT)" bash $(SECRETS_STAMP_SCRIPT) --check || REPO_ROOT="$(REPO_ROOT)" bash $(SECRETS_CHECK_SCRIPT) ) & p1=$$!; \
	( REPO_ROOT="$(REPO_ROOT)" bash $(GITIGNORE_STAMP_SCRIPT) --check ) & p2=$$!; \
	( REPO_ROOT="$(REPO_ROOT)" bash $(SECRETS_STAMP_SCRIPT) --check ) & p3=$$!; \
	( REPO_ROOT="$(REPO_ROOT)" bash $(LAN_IP_CHECK_SCRIPT) --check ) & p4=$$!; \
	\
	wait $$p1 || rc_secrets=$$?; \
	wait $$p2 || rc_git=$$?; \
	wait $$p3 || rc_sec_stamp=$$?; \
	wait $$p4 || rc_lan=$$?; \
	\
	total=$$((rc_secrets + rc_git + rc_sec_stamp + rc_lan)); \
	if [ $$total -ne 0 ]; then \
		echo "❌ repo-preflight FAILED"; \
		exit 1; \
	fi; \
	echo "✅ repo-preflight OK"


.PHONY: gitcheck update
gitcheck:
	@$(call git_clone_or_fetch,$(REPO_ROOT),$(HOMELAB_REPO),main); \
	echo "📜 homelab repo at commit $$(git -C $(REPO_ROOT) rev-parse --short HEAD)"

update: gitcheck
	@echo "⬆️ Updating homelab repo"; \
	git -C $(REPO_ROOT) pull --rebase || true; \
	echo "🔧 Repo now at commit $$(git -C $(REPO_ROOT) rev-parse --short HEAD)"
