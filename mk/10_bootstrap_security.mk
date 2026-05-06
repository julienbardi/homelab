# mk/10_bootstrap_security.mk
# ------------------------------------------------------------
# Security & Identity Bootstrap (Root-Locked / Multi-Operator)
# ------------------------------------------------------------

AGE_KEY_DIR  := /etc/sops/keys
AGE_KEY_FILE := $(AGE_KEY_DIR)/age.key

# mk/10_bootstrap_security.mk
# ------------------------------------------------------------
# Security & Identity Bootstrap (Root-Locked / Multi-Operator)
# ------------------------------------------------------------

AGE_KEY_DIR  := /etc/sops/keys
AGE_KEY_FILE := $(AGE_KEY_DIR)/age.key

# mk/10_bootstrap_security.mk
# ------------------------------------------------------------
# Security & Identity Bootstrap (Root-Locked / Multi-Operator)
# ------------------------------------------------------------

AGE_KEY_DIR  := /etc/sops/keys
AGE_KEY_FILE := $(AGE_KEY_DIR)/age.key

# mk/10_bootstrap_security.mk
# ------------------------------------------------------------
# Security & Identity Bootstrap (Root-Locked / Multi-Operator)
# ------------------------------------------------------------

AGE_KEY_DIR  := /etc/sops/keys
AGE_KEY_FILE := $(AGE_KEY_DIR)/age.key

.PHONY: security-bootstrap
security-bootstrap: install-pkg-age
	@if $(run_as_root) test -f "$(AGE_KEY_FILE)"; then \
		$(run_as_root) sh -c '\
			chown $(ROOT_UID):$(ROOT_GID) "$(AGE_KEY_DIR)" && \
			chmod 700 "$(AGE_KEY_DIR)" && \
			chown $(ROOT_UID):$(ROOT_GID) "$(AGE_KEY_FILE)" && \
			chmod 600 "$(AGE_KEY_FILE)" && \
			printf "%s\n" \
				"------------------------------------------------------------" \
				"✅ Age identity already exists at $(AGE_KEY_FILE)" \
				"🔒 Security: Owned by Root. Permissions: 0640." \
				"------------------------------------------------------------" \
				"📍 Public Encryption Key: $$(age-keygen -y "$(AGE_KEY_FILE)")" \
		'; \
	else \
		$(run_as_root) sh -c '\
			printf "%s\n" "🔐 Generating new homelab identity in $(AGE_KEY_DIR)..." && \
			install -d -o $(ROOT_UID) -g $(ROOT_GID) -m 700 "$(AGE_KEY_DIR)" && \
			age-keygen -o "$(AGE_KEY_FILE)" && \
			printf "%s\n" \
				"# ------------------------------------------------------------" \
				"# Source: See KeePass (Homelab/Infrastructure/AgeKey)" \
				"# Created by: mk/10_bootstrap_security.mk on $$(date)" \
				"# Operator: $(OPERATOR_USER)" \
				"# ------------------------------------------------------------" \
				>> "$(AGE_KEY_FILE)" && \
			chown $(ROOT_UID):$(ROOT_GID) "$(AGE_KEY_FILE)" && \
			chmod 600 "$(AGE_KEY_FILE)" && \
			printf "%s\n" \
				"✅ Identity created, commented, and locked to Root." \
				" " \
				"‼️  ACTION REQUIRED:" \
				"1. Copy the private key from: $(AGE_KEY_FILE)" \
				"2. Save in KeePass (Homelab/Infrastructure/AgeKey)" \
				"📍 Public Encryption Key: $$(age-keygen -y "$(AGE_KEY_FILE)")" \
		'; \
	fi


