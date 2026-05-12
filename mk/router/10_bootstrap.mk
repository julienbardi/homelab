# mk/router/10_bootstrap.mk
# ------------------------------------------------------------
# ROUTER BOOTSTRAP PRIMITIVES (NO ORCHESTRATION)
# ------------------------------------------------------------

ifeq ($(strip $(REPO_ROOT)),)
  $(error ❌ REPO_ROOT not set)
endif

REQUIRED_VARS := \
  INSTALL_FILE_IF_CHANGED \
  INSTALL_FILES_IF_CHANGED \
  INSTALL_IF_CHANGED_EXIT_CHANGED \
  run_as_root \
  ROUTER_SCRIPTS_OWNER \
  ROUTER_SCRIPTS_GROUP \
  ROUTER_SCRIPTS \
  ROUTER_SCRIPTS_MODE

ifneq ($(filter router-% wg-% dns-% firewall-% converge-% all,$(MAKECMDGOALS)),)
  MISSING_VARS := $(strip $(foreach v,$(REQUIRED_VARS),$(if $(strip $($(v))),, $(v))))
  ifneq ($(strip $(MISSING_VARS)),)
	$(error ❌ Missing required variables: $(subst  ,, $(MISSING_VARS)))
  endif
endif

# ------------------------------------------------------------
# SCRIPT PUSH HELPERS
# ------------------------------------------------------------

define PUSH_ROUTER_SCRIPTS_BATCH
	for f in $(ROUTER_SCRIPT_FILES); do \
		src="$(REPO_ROOT)/router/jffs/scripts/$$f"; \
		dst="$(ROUTER_SCRIPTS)/$$f"; \
		env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
			$(INSTALL_FILE_IF_CHANGED) -q \
				"" "" "$$src" \
				"$$ROUTER_ADDR" "$$ROUTER_SSH_PORT" "$$dst" \
				"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "$(ROUTER_SCRIPTS_MODE)"; \
		rc=$$?; \
		if [ $$rc -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
			rc=0; \
		fi; \
		if [ $$rc -ne 0 ]; then \
			echo "❌ Failed to push $$f to $$ROUTER_ADDR (rc=$$rc)"; \
			exit $$rc; \
		fi; \
	done; \
	exit 0
endef



define PUSH_ROUTER_SCRIPT
	find ~/.ssh -maxdepth 1 -type s -name 'cm-*' -delete 2>/dev/null || true

	if [ -z "$(VERBOSE)" ] || [ "$(VERBOSE)" -eq 0 ]; then \
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) -q \
		"" "" $(1) \
		$$ROUTER_ADDR $$ROUTER_SSH_PORT $(2) \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE); \
	else \
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) \
		"" "" $(1) \
		$$ROUTER_ADDR $$ROUTER_SSH_PORT $(2) \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE); \
	fi; \
	rc=$$?; \
	if [ $$rc -ne 0 ] && [ $$rc -ne $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
	echo "❌ Failed to push $(1) to $$ROUTER_ADDR (rc=$$rc)"; \
	exit $$rc; \
	fi
endef

# ------------------------------------------------------------
# PHASE 0: INFRASTRUCTURE & BOOTSTRAP
# ------------------------------------------------------------

.PHONY: ensure-default-gateway
ensure-default-gateway: secrets-ready
	@$(WITH_SECRETS) \
		if ! ip route show default | grep -q "$$ROUTER_ADDR"; then \
			echo "⚠️ Default gateway missing! Restoring path to $$ROUTER_ADDR..."; \
			$(run_as_root) ip route add default via "$$ROUTER_ADDR" dev $(LAN_IFACE) 2>/dev/null || true; \
			echo "✅ Default gateway restored"; \
		else \
			echo "🟢 Default gateway OK"; \
		fi

.PHONY: router-bootstrap-run-as-root
router-bootstrap-run-as-root: secrets-ready ensure-default-gateway
	@echo "🛡️ Bootstrapping run-as-root on router"
	@$(WITH_SECRETS) \
		ssh -p "$$ROUTER_SSH_PORT" "$$ROUTER_USER@$$ROUTER_ADDR" \
			'set -e; mkdir -p /jffs/scripts; cat > /jffs/scripts/run-as-root; chmod 0755 /jffs/scripts/run-as-root' \
		< $(REPO_ROOT)/router/jffs/scripts/run-as-root.sh
	@echo "✅ run-as-root installed"

ROUTER_ULA_FILE := /etc/homelab/router-ula
ROUTER_ULA_VALUE := fd89:7a3b:42c0::1

.tmp/router-ula:
	@mkdir -p .tmp
	@printf "%s\n" "$(ROUTER_ULA_VALUE)" > .tmp/router-ula

.PHONY: ensure-router-ula
ensure-router-ula: secrets-ready router-bootstrap-run-as-root | $(INSTALL_FILES_IF_CHANGED)
	@echo "🧩 Ensuring router ULA ($(ROUTER_ULA_VALUE))"

	$(call TMPFILE_BLOCK,"$(TMP_ROUTER_ULA)", \
		printf "%s\n" "$(ROUTER_ULA_VALUE)" > "$(TMP_ROUTER_ULA)"; \

		$(WITH_SECRETS) \
			env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
				$(INSTALL_FILE_IF_CHANGED) \
					"" "" "$(TMP_ROUTER_ULA)" \
					"$$ROUTER_ADDR" "$$ROUTER_SSH_PORT" "$(ROUTER_ULA_FILE)" \
					"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
			|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
	)

.PHONY: ensure-router-known-hosts
ensure-router-known-hosts: router-bootstrap-run-as-root
	@echo "🔐 Ensuring NAS host key is trusted on router"

	# Generate NAS host key line on NAS
	@NAS_KEY_LINE="$$(ssh-keyscan -p 2222 10.89.12.4 2>/dev/null)"; \
	if [ -z "$$NAS_KEY_LINE" ]; then \
		echo "❌ Failed to obtain NAS host key via ssh-keyscan"; \
		exit 1; \
	fi; \

	# Push to router if missing
	ssh -p "$$ROUTER_SSH_PORT" "$$ROUTER_USER@$$ROUTER_ADDR" "\
		mkdir -p /root/.ssh && chmod 700 /root/.ssh; \
		grep -q \"\[$(nas_lan_ip)\]:2222\" /root/.ssh/known_hosts 2>/dev/null || { \
			echo \"🔑 Adding NAS host key\"; \
			echo \"$$NAS_KEY_LINE\" >> /root/.ssh/known_hosts; \
			chmod 600 /root/.ssh/known_hosts; \
		} \
	"

	@echo "🟢 NAS host key trusted"

# ------------------------------------------------------------
# SCRIPT DEPLOYMENT ONLY
# ------------------------------------------------------------

ROUTER_SCRIPT_FILES := \
	caddy-reload.sh certs-create.sh certs-deploy.sh common.sh \
	gen-client-cert-wrapper.sh generate-client-cert.sh \
	firewall-start \
	install-cert.sh \
	wan-event

.PHONY: router-install-%
router-install-%: | router-bootstrap-run-as-root
	@src=$(REPO_ROOT)/router/jffs/scripts/$*; \
	if [ ! -f "$$src" ]; then \
	  echo "⚠️ Skipping $* — source $$src not found"; \
	else \
	  $(call PUSH_ROUTER_SCRIPT, $$src, $(ROUTER_SCRIPTS)/$*); \
	fi

.PHONY: router-install-scripts
router-install-scripts: install-ssh-config \
	router-bootstrap-run-as-root \
	ensure-router-known-hosts | ensure-router-ula
	@echo "📤 Deploying router scripts to $(ROUTER_ADDR):$(ROUTER_SCRIPTS)"
	@echo "   Files: $(words $(ROUTER_SCRIPT_FILES))"

	@{ $(call PUSH_ROUTER_SCRIPTS_BATCH); } || true

	@echo "🟢 Router scripts installed — $(words $(ROUTER_SCRIPT_FILES)) files deployed"

# ------------------------------------------------------------
# NO ORCHESTRATION BELOW THIS LINE
# ------------------------------------------------------------

.PHONY: router-firewall-install
router-firewall-install: | ensure-router-ula
	@true
