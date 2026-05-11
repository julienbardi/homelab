# mk/10_bootstrap_security.mk
# ------------------------------------------------------------
# Security & Identity Bootstrap (Root-Locked / Multi-Operator)
# ------------------------------------------------------------

AGE_KEY_DIR  := /etc/sops/keys
AGE_KEY_FILE := $(AGE_KEY_DIR)/age.key

.PHONY: security-bootstrap
security-bootstrap: install-pkg-age
	@set -euo pipefail; \
	if $(run_as_root) test -f "$(AGE_KEY_FILE)"; then \
		echo "------------------------------------------------------------"; \
		echo "🔒 AGE identity already exists at $(AGE_KEY_FILE)"; \
		echo "❌ Refusing to overwrite existing root-locked identity"; \
		echo "   This is the canonical homelab key. Bootstrap will not modify it."; \
		echo "------------------------------------------------------------"; \
		exit 0; \
	fi; \
	echo "------------------------------------------------------------"; \
	echo "🔐 No AGE identity found. Creating canonical homelab identity..."; \
	$(run_as_root) install -d -o $(ROOT_UID) -g $(ROOT_GID) -m 700 "$(AGE_KEY_DIR)"; \
	$(run_as_root) age-keygen -o "$(AGE_KEY_FILE)"; \
	$(run_as_root) sh -c '\
		printf "%s\n" \
			"# ------------------------------------------------------------" \
			"# Source: See KeePass (Homelab/Infrastructure/AgeKey)" \
			"# Created by: mk/10_bootstrap_security.mk on $$(date)" \
			"# Operator: $(OPERATOR_USER)" \
			"# ------------------------------------------------------------" \
			>> "$(AGE_KEY_FILE)" \
	'; \
	$(run_as_root) chown $(ROOT_UID):$(ROOT_GID) "$(AGE_KEY_FILE)"; \
	$(run_as_root) chmod 600 "$(AGE_KEY_FILE)"; \
	echo "✅ Identity created and locked to root."; \
	echo "‼️ ACTION REQUIRED: Copy the private key from $(AGE_KEY_FILE) into KeePass NOW."; \
	echo "📍 Public Encryption Key:"; \
	$(run_as_root) age-keygen -y "$(AGE_KEY_FILE)"; \
	echo "------------------------------------------------------------"



