# ============================================================
# mk/21_invariants_stamps.mk — stamp metadata for all invariants
# ============================================================

# All invariant stamps must use user-level stamp directory
STAMP_DIR := $(STAMP_DIR_USER)

# ------------------------------
# gitignore-check
# ------------------------------
GITIGNORE_STAMP := $(STAMP_DIR)/gitignore-check.stamp

define compute_gitignore_hash
	git ls-files -z | xargs -0 sha256sum | sha256sum | awk '{print $$1}'
endef


# ------------------------------
# secrets-check
# ------------------------------
SECRETS_STAMP := $(STAMP_DIR)/secrets-check.stamp

define compute_secrets_hash
	git ls-files -z | xargs -0 sha256sum | sha256sum | awk '{print $$1}'
endef
