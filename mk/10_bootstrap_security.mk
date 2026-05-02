# mk/10_bootstrap_security.mk
# ------------------------------------------------------------
# Security & Identity Bootstrap (Root-Locked / Multi-Operator)
# ------------------------------------------------------------

AGE_KEY_DIR  := /etc/sops/keys
AGE_KEY_FILE := $(AGE_KEY_DIR)/age.key

.PHONY: security-bootstrap
security-bootstrap: install-pkg-age
	@if [ -f "$(AGE_KEY_FILE)" ]; then \
		echo "------------------------------------------------------------"; \
		echo "✅ Age identity already exists at $(AGE_KEY_FILE)"; \
		echo "🔒 Security: Owned by Root. Permissions: 0640."; \
		echo "------------------------------------------------------------"; \
	else \
		echo "🔐 Generating new homelab identity in $(AGE_KEY_DIR)..."; \
		$(run_as_root) mkdir -p "$(AGE_KEY_DIR)"; \
		$(run_as_root) chown $(ROOT_UID):$(ROOT_GID) "$(AGE_KEY_DIR)"; \
		$(run_as_root) chmod 711 "$(AGE_KEY_DIR)"; \
		$(run_as_root) age-keygen -o "$(AGE_KEY_FILE)"; \
		printf "%s\n" \
			"# ------------------------------------------------------------" \
			"# Source: See KeePass (Homelab/Infrastructure/AgeKey)" \
			"# Created by: mk/10_bootstrap_security.mk on $$(date)" \
			"# Operator: $(OPERATOR_USER)" \
			"# ------------------------------------------------------------" \
			| $(run_as_root) tee -a "$(AGE_KEY_FILE)" >/dev/null; \
		$(run_as_root) chown $(ROOT_UID):$(ROOT_GID) "$(AGE_KEY_FILE)"; \
		$(run_as_root) chmod 600 "$(AGE_KEY_FILE)"; \
		echo "✅ Identity created, commented, and locked to Root."; \
		echo ""; \
		echo "‼️  ACTION REQUIRED:"; \
		echo "1. Copy the private key from: $(AGE_KEY_FILE)"; \
		echo "2. Save in KeePass (Homelab/Infrastructure/AgeKey)"; \
	fi
	@echo "📍 Your Public Key (Lock) is: $$($(run_as_root) age-keygen -y $(AGE_KEY_FILE))"
