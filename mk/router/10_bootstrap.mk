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

define PUSH_ROUTER_SCRIPT
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
	@$(call WITH_SECRETS, sh -c '\
		if ! ip route show default | grep -q "$$ROUTER_ADDR"; then \
			echo "⚠️ Default gateway missing! Restoring path to $$ROUTER_ADDR..."; \
			$(run_as_root) ip route add default via "$$ROUTER_ADDR" dev $(LAN_IFACE) 2>/dev/null || true; \
			echo "✅ Default gateway restored"; \
		else \
			echo "🟢 Default gateway OK"; \
		fi \
	')

.PHONY: router-ensure-scripts-dir
router-ensure-scripts-dir:
	@true

.PHONY: router-bootstrap-primitives
router-bootstrap-primitives: secrets-ready ensure-default-gateway
	@echo "🛡️ Bootstrapping router primitives (run-as-root + install-cert.sh + reset-router.sh)"

	# Step 1: local hashes
	@LOCAL_HASH_RUN_AS_ROOT="$$(sha256sum "$(REPO_ROOT)/router/jffs/scripts/run-as-root.sh" | awk '{print $$1}')" ; \
	LOCAL_HASH_INSTALL_CERT="$$(sha256sum "$(REPO_ROOT)/router/jffs/scripts/install-cert.sh" | awk '{print $$1}')" ; \
	LOCAL_HASH_RESET_ROUTER="$$(sha256sum "$(REPO_ROOT)/router/jffs/scripts/reset-router.sh" | awk '{print $$1}')" ; \

	# Step 2: single SSH — ensure dirs, known_hosts state, remote hashes
	REMOTE_DATA="$$(ssh $(SSH_HOST_ROUTER) '\
		mkdir -p /jffs/scripts && chmod 755 /jffs/scripts && chown 0:0 /jffs/scripts ; \
		mkdir -p /root/.ssh && chmod 700 /root/.ssh ; \
		if ! grep -q \"[$(LAN_NAS)]:2222\" /root/.ssh/known_hosts 2>/dev/null; then \
			echo MISSING_KNOWN_HOST ; \
		else \
			echo OK_KNOWN_HOST ; \
		fi ; \
		[ -f /jffs/scripts/run-as-root ] && sha256sum /jffs/scripts/run-as-root || echo MISSING ; \
		[ -f /jffs/scripts/install-cert.sh ] && sha256sum /jffs/scripts/install-cert.sh || echo MISSING ; \
		[ -f /jffs/scripts/reset-router.sh ] && sha256sum /jffs/scripts/reset-router.sh || echo MISSING ; \
	')" ; \

	REMOTE_KNOWN_HOST="$$(printf "%s" "$$REMOTE_DATA" | sed -n '1p')" ; \
	REMOTE_HASH_RUN_AS_ROOT="$$(printf "%s" "$$REMOTE_DATA" | sed -n '2p' | awk '{print $$1}')" ; \
	REMOTE_HASH_INSTALL_CERT="$$(printf "%s" "$$REMOTE_DATA" | sed -n '3p' | awk '{print $$1}')" ; \
	REMOTE_HASH_RESET_ROUTER="$$(printf "%s" "$$REMOTE_DATA" | sed -n '4p' | awk '{print $$1}')" ; \

	# Step 3: fix known-hosts if missing
	if [ "$$REMOTE_KNOWN_HOST" = "MISSING_KNOWN_HOST" ]; then \
		echo "🔑 Adding NAS host key" ; \
		NAS_KEY_LINE="$$(ssh-keyscan -p 2222 $(LAN_NAS) 2>/dev/null)" ; \
		if [ -z "$$NAS_KEY_LINE" ]; then \
			echo "❌ Failed to obtain NAS host key via ssh-keyscan" ; \
			exit 1 ; \
		fi ; \
		ssh $(SSH_HOST_ROUTER) "echo \"$$NAS_KEY_LINE\" >> /root/.ssh/known_hosts && chmod 600 /root/.ssh/known_hosts" ; \
	fi ; \

	# Step 4: compare hashes
	if [ "$$REMOTE_HASH_RUN_AS_ROOT" = "$$LOCAL_HASH_RUN_AS_ROOT" ] && \
	   [ "$$REMOTE_HASH_INSTALL_CERT" = "$$LOCAL_HASH_INSTALL_CERT" ] && \
	   [ "$$REMOTE_HASH_RESET_ROUTER" = "$$LOCAL_HASH_RESET_ROUTER" ]; then \
		echo "🟢 Bootstrap primitives already up-to-date" ; \
		exit 0 ; \
	fi ; \

	# Step 5: slow path — stream all three
	echo "📝 Updating bootstrap primitives on router (content drift detected)" ; \
	\
	cat "$(REPO_ROOT)/router/jffs/scripts/run-as-root.sh" | \
	ssh $(SSH_HOST_ROUTER) "\
		umask 022; \
		cat > /jffs/scripts/run-as-root && \
		chown 0:0 /jffs/scripts/run-as-root && \
		chmod 0755 /jffs/scripts/run-as-root" ; \
	\
	cat "$(REPO_ROOT)/router/jffs/scripts/install-cert.sh" | \
	ssh $(SSH_HOST_ROUTER) "\
		umask 022; \
		cat > /jffs/scripts/install-cert.sh && \
		chown 0:0 /jffs/scripts/install-cert.sh && \
		chmod 0755 /jffs/scripts/install-cert.sh" ; \
	\
	cat "$(REPO_ROOT)/router/jffs/scripts/reset-router.sh" | \
	ssh $(SSH_HOST_ROUTER) "\
		umask 022; \
		cat > /jffs/scripts/reset-router.sh && \
		chown 0:0 /jffs/scripts/reset-router.sh && \
		chmod 0755 /jffs/scripts/reset-router.sh" ; \
	\
	echo "✅ Router primitives installed"

ROUTER_ULA_FILE := /etc/homelab/router-ula
ROUTER_ULA_VALUE := fd89:7a3b:42c0::1

.tmp/router-ula:
	@mkdir -p .tmp
	@printf "%s\n" "$(ROUTER_ULA_VALUE)" > .tmp/router-ula

.PHONY: ensure-router-ula
ensure-router-ula: secrets-ready router-bootstrap-primitives | $(INSTALL_FILES_IF_CHANGED)
	@echo "🧩 Ensuring router ULA ($(ROUTER_ULA_VALUE))"

	$(call TMPFILE_BLOCK,"$(TMP_ROUTER_ULA)", \
		TMPFILE="$(TMP_ROUTER_ULA)"; \
		printf "%s\n" "$(ROUTER_ULA_VALUE)" > "$$TMPFILE"; \
		$(call WITH_SECRETS, sh -c '\
			env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
				$(INSTALL_FILE_IF_CHANGED) \
					"" "" "'"$$TMPFILE"'" \
					"$$ROUTER_ADDR" "$$ROUTER_SSH_PORT" "$(ROUTER_ULA_FILE)" \
					"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
				|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
		') \
	)

.PHONY: ensure-router-known-hosts
ensure-router-known-hosts: install-ssh-config
	@echo "🔐 Ensuring NAS host key is trusted on router (handled in bootstrap)"
	@true

# ------------------------------------------------------------
# SCRIPT DEPLOYMENT ONLY
# ------------------------------------------------------------

ROUTER_SCRIPT_FILES := \
	caddy-reload.sh certs-create.sh certs-deploy.sh common.sh \
	gen-client-cert-wrapper.sh generate-client-cert.sh \
	firewall-start \
	wan-event \
	services-start \
	dns-enforcer.sh \
	ipv6-watchdog.sh \
	dhcp6c-state \
	ddns-start \
	wan-reset.sh

.PHONY: router-install-%
router-install-%: | router-bootstrap-primitives
	@src=$(REPO_ROOT)/router/jffs/scripts/$*; \
	if [ ! -f "$$src" ]; then \
	  echo "⚠️ Skipping $* — source $$src not found"; \
	else \
	  $(call PUSH_ROUTER_SCRIPT, $$src, $(ROUTER_SCRIPTS)/$*); \
	fi

.PHONY: router-install-scripts
router-install-scripts: install-ssh-config \
	ensure-router-known-hosts router-scripts-invariants | ensure-router-ula
	@echo "🔍 Router script converge (non‑vectorized, deterministic)"

	@set -e; \
	for f in \
		caddy-reload.sh \
		certs-create.sh \
		certs-deploy.sh \
		common.sh \
		gen-client-cert-wrapper.sh \
		generate-client-cert.sh \
		firewall-start \
		wan-event \
		services-start \
		dns-enforcer.sh \
		ipv6-watchdog.sh \
		dhcp6c-state \
		ddns-start \
		wan-reset.sh \
		dnsmasq-ready.sh; \
	do \
		src="$(REPO_ROOT)/router/jffs/scripts/$$f"; \
		dst="$(ROUTER_SCRIPTS)/$$f"; \
		if [ ! -f "$$src" ]; then \
			echo "⚠️ Skipping $$f — source $$src not found"; \
			continue; \
		fi; \
		echo "➡️  Installing $$f"; \
		rc=0; \
		env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
			$(INSTALL_FILE_IF_CHANGED) \
				"" "" "$$src" \
				"$$ROUTER_ADDR" "$$ROUTER_SSH_PORT" "$$dst" \
				"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "$(ROUTER_SCRIPTS_MODE)" \
		|| rc=$$?; \
		if [ "$$rc" -eq "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
			echo "📝 $$f updated"; \
		elif [ "$$rc" -ne 0 ]; then \
			echo "❌ Failed to install $$f (rc=$$rc)"; \
			exit $$rc; \
		else \
			echo "🟢 $$f already up-to-date"; \
		fi; \
	done

	@echo "🟢 All router scripts processed"


.PHONY: router-scripts-invariants
router-scripts-invariants: | router-ssh-check
	@echo "🛡️ Enforcing /jffs/scripts ownership + permissions invariants"

	@ssh $(SSH_HOST_ROUTER) '\
		set -e; \
		if [ -d /jffs/scripts ]; then \
			# Ownership invariant
			/jffs/scripts/run-as-root chown -R julie:root /jffs/scripts; \
			\
			# Hook scripts (executed by AsusWRT) → 755
			for f in services-start firewall-start wan-event dnsmasq-ready.sh wg-firewall.sh; do \
				if [ -f /jffs/scripts/$$f ]; then \
					/jffs/scripts/run-as-root chmod 755 /jffs/scripts/$$f; \
				fi; \
			done; \
			\
			# Control-plane scripts → 700
			for f in ipv6-watchdog.sh wan-reset.sh common.sh homelab-prefix-watchdog.sh; do \
				if [ -f /jffs/scripts/$$f ]; then \
					/jffs/scripts/run-as-root chmod 700 /jffs/scripts/$$f; \
				fi; \
			done; \
			\
			# State files → 600
			for f in .ipv6_watchdog_state dhcp6c-state; do \
				if [ -f /jffs/scripts/$$f ]; then \
					/jffs/scripts/run-as-root chmod 600 /jffs/scripts/$$f; \
				fi; \
			done; \
		fi; \
		echo "🟢 /jffs/scripts invariants enforced"; \
	'


print-ROUTER_SCRIPT_FILES:
	@printf '%q\n' $(ROUTER_SCRIPT_FILES)
print-ROUTER_SCRIPTS_OWNER:
	@echo 'OWNER="$(ROUTER_SCRIPTS_OWNER)"'

print-ROUTER_SCRIPTS_GROUP:
	@echo 'GROUP="$(ROUTER_SCRIPTS_GROUP)"'

print-ROUTER_SCRIPTS_MODE:
	@echo 'MODE="$(ROUTER_SCRIPTS_MODE)"'
