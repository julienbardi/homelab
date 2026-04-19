# mk/07_secrets.mk
# ------------------------------------------------------------
# Secret Management: SOPS/Age Decryption Orchestration
# ------------------------------------------------------------
SECRETS_SRC := secrets.enc.yaml

.PHONY: secrets-gen-ddns check-secrets-src sops-init

# --- 1. Entry Point ---
secrets-gen-ddns: $(DDNS_TARGET)

# --- 2. Operational Logic ---
$(DDNS_TARGET): $(SECRETS_SRC) $(AGE_KEY_FILE)
	@$(MAKE) check-secrets-src
	@echo "🔐 Source changed. Decrypting secrets into $@..."
	@$(run_as_root) bash -c '\
		export SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE); \
		TOPDOMAIN=$$(sops -d --extract "[\"ddns\"][\"topdomain\"]" $(SECRETS_SRC)); \
		USER=$$(sops -d --extract "[\"ddns\"][\"username\"]" $(SECRETS_SRC)); \
		PASS=$$(sops -d --extract "[\"ddns\"][\"password\"]" $(SECRETS_SRC)); \
		printf "DNS_TOPDOMAIN_NAME=$$TOPDOMAIN\nDDNSUSERNAME=$$USER\nDDNSPASSWORD=$$PASS\n" > $@.tmp; \
		chown $(ROOT_UID):$(ROOT_GID) $@.tmp; \
		chmod 0640 $@.tmp; \
		mv $@.tmp $@;'
	@echo "✅ $@ updated."

# --- 3. Configuration & Guards ---
sops-init:
	@if [ ! -f ".sops.yaml" ] || ! grep -Fq "$(SOPS_AGE_PUBKEY)" ".sops.yaml"; then \
		echo "⚙️ Configuring .sops.yaml (Identity: $(SOPS_AGE_PUBKEY))..."; \
		printf "creation_rules:\n  - path_regex: $(SECRETS_SRC)$$\n    age: $(SOPS_AGE_PUBKEY)\n" > .sops.yaml; \
	fi

check-secrets-src: sops-init
	@if [ ! -f "$(SECRETS_SRC)" ]; then \
		echo "❌ Error: $(SECRETS_SRC) not found!"; \
		echo "👉 Required One-Time Activity:"; \
		echo "   export SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE)"; \
		echo "   sops $(SECRETS_SRC)"; \
		exit 1; \
	fi