# mk/30_secrets.mk
# ============================================================================
# mk/30_secrets.mk — Secret presence and structural enforcement
# ----------------------------------------------------------------------------
# PURPOSE:
#   This layer enforces the existence, ownership, permissions, and structural
#   validity of secret material required by the homelab. It validates contracts
#   without inspecting or coupling to secret content.
#
# CONTRACT:
#   - Secrets are never generated here.
#   - Secret values are never logged, hashed, or embedded in code.
#   - Validation is structural only (presence, permissions, required keys).
#   - All filesystem mutation is explicit and idempotent.
#
# SCOPE:
#   - Directory creation with strict permissions
#   - Secret file presence and mode enforcement
#   - Structural validation (required variables, non-empty)
#
# NON-GOALS:
#   - Secret rotation
#   - Functional validation against external services
#   - Runtime deployment to remote hosts
# ============================================================================
.PHONY: ddns-secret-ensure
ddns-secret-ensure:
	@echo "🔐 Ensuring DDNS secret directory"
	@$(INSTALL_PATH)/ensure_dir.sh root admin 0750 "$(DDNS_SECRET_DIR)"

	@echo "🔍 Checking DDNS secret file presence"
	@if ! sudo test -f "$(DDNS_SECRET_FILE)"; then \
		echo "❌ Missing DDNS secret file:"; \
		echo "   $(DDNS_SECRET_FILE)"; \
		echo ""; \
		echo "➡️  Create it with:"; \
		echo "   sudoedit $(DDNS_SECRET_FILE)"; \
		echo ""; \
		echo "   Required variables:"; \
		echo "     DNS_TOPDOMAIN_NAME"; \
		echo "     DDNSUSERNAME"; \
		echo "     DDNSPASSWORD"; \
		exit 1; \
	fi

	@echo "🔒 Enforcing ownership and permissions"
	@sudo stat -c '%U:%G:%a' "$(DDNS_SECRET_FILE)" | grep -qx 'root:admin:640' || \
		{ sudo chown root:admin "$(DDNS_SECRET_FILE)"; sudo chmod 0640 "$(DDNS_SECRET_FILE)"; }

	@echo "🧪 Validating DDNS secret structure"
	@missing=0; \
	for var in DNS_TOPDOMAIN_NAME DDNSUSERNAME DDNSPASSWORD; do \
		if ! grep -Eq "^[[:space:]]*$$var=['\"][^'\"]+['\"]" "$(DDNS_SECRET_FILE)"; then \
			echo "❌ Missing or empty variable: $$var"; \
			missing=1; \
		fi; \
	done; \
	if [ $$missing -ne 0 ]; then \
		echo ""; \
		echo "➡️  Edit the file:"; \
		echo "   sudoedit $(DDNS_SECRET_FILE)"; \
		exit 1; \
	fi

	@echo "✅ DDNS secret present, secure, and structurally valid"

.PHONY: router-ddns-check
router-ddns-check: ddns-secret-ensure
	@echo "🌐 Verifying DDNS update on router"
	@# Functional validation (idempotent at provider level; safe to re-run)
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '/jffs/scripts/ddns-start'
