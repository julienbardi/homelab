# mk/10_bootstrap_security.mk
# ------------------------------------------------------------
# Security & Identity Bootstrap (Root-Locked / Multi-Operator)
# ------------------------------------------------------------
# Owner: root:root (ROOT_UID:ROOT_GID)
# Mode:  0640 (Root can RW, Root-Group/Admins can Read)

AGE_KEY_DIR  := $(HOMELAB_DIR)/secrets
AGE_KEY_FILE := $(AGE_KEY_DIR)/age.key

.PHONY: security-bootstrap
security-bootstrap: guard-config install-pkg-age
	@if [ -f "$(AGE_KEY_FILE)" ]; then \
		echo "------------------------------------------------------------"; \
		echo "✅ Age identity already exists at $(AGE_KEY_FILE)"; \
		echo "🔒 Security: Owned by Root. Permissions: 0640."; \
		echo "------------------------------------------------------------"; \
	else \
		echo "🔐 Generating new homelab identity in $(AGE_KEY_DIR)..."; \
		$(run_as_root) mkdir -p $(AGE_KEY_DIR); \
		$(run_as_root) bash -c ' \
			age-keygen -o $(AGE_KEY_FILE); \
			{ \
				echo "# ------------------------------------------------------------"; \
				echo "# Source: See KeePass (Homelab/Infrastructure/AgeKey)"; \
				echo "# Created by: mk/10_bootstrap_security.mk on $$(date)"; \
				echo "# Operator: $(OPERATOR_USER)"; \
				echo "# ------------------------------------------------------------"; \
			} >> $(AGE_KEY_FILE); \
		'; \
		$(run_as_root) chown $(ROOT_UID):$(ROOT_GID) $(AGE_KEY_FILE); \
		$(run_as_root) chmod 640 $(AGE_KEY_FILE); \
		echo "✅ Identity created, commented, and locked to Root."; \
		echo ""; \
		echo "‼️  ACTION REQUIRED:"; \
		echo "1. Copy the private key from: $(AGE_KEY_FILE)"; \
		echo "2. Save in KeePass (Homelab/Infrastructure/AgeKey)"; \
	fi
	@echo "📍 Your Public Key (Lock) is: $$($(run_as_root) age-keygen -y $(AGE_KEY_FILE))"