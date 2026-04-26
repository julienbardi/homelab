# mk/07_secrets.mk
# ============================================================================
# Secret Management: SOPS/Age Decryption Orchestration
# and Secret presence and structural enforcement
# ============================================================================

SOPS := /usr/local/bin/sops
SECRETS_FILE := secrets.enc.yaml
TMP_DDNS_CONF := /tmp/ddns.conf

# ----------------------------------------------------------------------------
# 1. SOPS CONFIGURATION & GUARDS
# ----------------------------------------------------------------------------

.PHONY: sops-init
sops-init:
	@if [ ! -f ".sops.yaml" ] || ! grep -Fq "$(SOPS_AGE_PUBKEY)" ".sops.yaml"; then \
		echo "⚙️ Configuring .sops.yaml (Identity: $(SOPS_AGE_PUBKEY))..."; \
		printf "creation_rules:\n  - path_regex: $(SECRETS_FILE)$$\n    age: $(SOPS_AGE_PUBKEY)\n" > .sops.yaml; \
	fi

.PHONY: check-secrets-src
check-secrets-src: sops-init
	@if [ ! -f "$(SECRETS_FILE)" ]; then \
		echo "❌ Error: $(SECRETS_FILE) not found!"; \
		echo "👉 Required One-Time Activity:"; \
		echo "   SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE)"; \
		echo "   sops $(SECRETS_FILE)"; \
		exit 1; \
	fi

.PHONY: print-age-key-file
print-age-key-file:
	@echo "AGE_KEY_FILE = '$(AGE_KEY_FILE)'"

# ----------------------------------------------------------------------------
# 2. secrets-load — decrypt once, load into memory only
# ----------------------------------------------------------------------------

.PHONY: secrets-load
secrets-load: check-secrets-src
	@tmpfile=$$(mktemp); \
	sops -d $(SECRETS_FILE) > $$tmpfile; \
	\
	STATIC_DHCP=$$(awk '\
		/^dhcp_staticlist:/ {block=1; next} \
		block==1 && /^[ ]/ { \
			line=$$0; sub(/^[ ]+/, "", line); \
			printf "%s ", line; next \
		} \
		block==1 && !/^[ ]/ {block=0} \
	' $$tmpfile | sed 's/[ ]*$$//'); \
	\
	DDNS_TOPDOMAIN=$$(awk -F': *' '/^[ ]*topdomain:/ {print $$2}' $$tmpfile); \
	DDNS_USERNAME=$$(awk -F': *' '/^[ ]*username:/ {print $$2}' $$tmpfile); \
	DDNS_PASSWORD=$$(awk -F': *' '/^[ ]*password:/ {print $$2}' $$tmpfile); \
	\
	rm -f $$tmpfile; \
	\
	export STATIC_DHCP="$$STATIC_DHCP"; \
	export DDNS_TOPDOMAIN="$$DDNS_TOPDOMAIN"; \
	export DDNS_USERNAME="$$DDNS_USERNAME"; \
	export DDNS_PASSWORD="$$DDNS_PASSWORD"; \
	echo "🔐 Secrets loaded into memory"

# ----------------------------------------------------------------------------
# 3. ddns-conf-generate — ephemeral RAM-only file
# ----------------------------------------------------------------------------

.PHONY: ddns-conf-generate
ddns-conf-generate: secrets-load
	@echo "DNS_TOPDOMAIN_NAME=$(DDNS_TOPDOMAIN)" > $(TMP_DDNS_CONF)
	@echo "DDNSUSERNAME=$(DDNS_USERNAME)" >> $(TMP_DDNS_CONF)
	@echo "DDNSPASSWORD=$(DDNS_PASSWORD)" >> $(TMP_DDNS_CONF)
	@chmod 600 $(TMP_DDNS_CONF)
	@echo "🧩 Generated $(TMP_DDNS_CONF) (RAM only)"

# ----------------------------------------------------------------------------
# 4. router-ddns-check & ddns-start (unchanged)
# ----------------------------------------------------------------------------

.PHONY: router-ddns-check
router-ddns-check: router-ddns
	@echo "🌐 Verifying DDNS update on router"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '/jffs/scripts/ddns-start'

.PHONY: ddns-start
ddns-start: router-ddns-check
	@echo "🚀 DDNS start sequence completed"
