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
# PHASE 0: INFRASTRUCTURE & BOOTSTRAP
# ------------------------------------------------------------


.PHONY: router-ensure-scripts-dir
router-ensure-scripts-dir:
	@true

.PHONY: router-bootstrap-primitives
router-bootstrap-primitives: secrets-ready ensure-host-default-route
	@echo "🛡️ Bootstrapping router primitives"; \
	\
	# Ensure necessary directories exist for $(INSTALL_FILE_IF_CHANGED) \
	ssh $(SSH_HOST_ROUTER) "mkdir -p /jffs/scripts /etc/homelab"; \
	\
	# Step 1: local hashes \
	LOCAL_HASH_RUN_AS_ROOT="$$(sha256sum "$(REPO_ROOT)/router/jffs/scripts/run-as-root.sh" | awk '{print $$1}')" ; \
	LOCAL_HASH_INSTALL_CERT="$$(sha256sum "$(REPO_ROOT)/router/jffs/scripts/install-cert.sh" | awk '{print $$1}')" ; \
	LOCAL_HASH_RESET_ROUTER="$$(sha256sum "$(REPO_ROOT)/router/jffs/scripts/reset-router.sh" | awk '{print $$1}')" ; \
	\
	# Step 2: single SSH — ensure dirs, verify known_hosts cleanly, fetch remote hashes with structured tags \
	REMOTE_DATA="$$(ssh $(SSH_HOST_ROUTER) '\
		mkdir -p /jffs/scripts && chmod 755 /jffs/scripts && chown 0:0 /jffs/scripts ; \
		mkdir -p /root/.ssh && chmod 700 /root/.ssh ; \
		mkdir -p /jffs/ssl && chmod 700 /jffs/ssl ; \
		if ! grep -Fq "$(LAN_NAS):2222" /root/.ssh/known_hosts 2>/dev/null && ! grep -Fq "[$(LAN_NAS)]:2222" /root/.ssh/known_hosts 2>/dev/null; then \
			echo "STATUS_KNOWN_HOST:MISSING" ; \
		else \
			echo "STATUS_KNOWN_HOST:OK" ; \
		fi ; \
		echo -n "HASH_RUN_AS_ROOT:" ; [ -f /jffs/scripts/run-as-root ] && sha256sum /jffs/scripts/run-as-root | awk "{print \$$1}" || echo "MISSING" ; \
		echo -n "HASH_INSTALL_CERT:" ; [ -f /jffs/scripts/install-cert.sh ] && sha256sum /jffs/scripts/install-cert.sh | awk "{print \$$1}" || echo "MISSING" ; \
		echo -n "HASH_RESET_ROUTER:" ; [ -f /jffs/scripts/reset-router.sh ] && sha256sum /jffs/scripts/reset-router.sh | awk "{print \$$1}" || echo "MISSING" ; \
	')" ; \
	\
	# Extract tags — SINGLE-LINE, MAKE-SAFE, NO COLLAPSING \
	REMOTE_KNOWN_HOST="$$(printf "%s" "$$REMOTE_DATA" | grep "^STATUS_KNOWN_HOST:" | cut -d: -f2 || echo UNSET)" ; \
	if [ "$$REMOTE_KNOWN_HOST" = "UNSET" ]; then \
		echo "❌ router-bootstrap: missing STATUS_KNOWN_HOST tag in remote output"; \
		printf "%s\n" "$$REMOTE_DATA"; \
		exit 1; \
	fi; \
	\
	REMOTE_HASH_RUN_AS_ROOT="$$(printf "%s" "$$REMOTE_DATA" | grep "^HASH_RUN_AS_ROOT:" | cut -d: -f2 || echo UNSET)" ; \
	REMOTE_HASH_INSTALL_CERT="$$(printf "%s" "$$REMOTE_DATA" | grep "^HASH_INSTALL_CERT:" | cut -d: -f2 || echo UNSET)" ; \
	REMOTE_HASH_RESET_ROUTER="$$(printf "%s" "$$REMOTE_DATA" | grep "^HASH_RESET_ROUTER:" | cut -d: -f2 || echo UNSET)" ; \
	\
	if [ "$$REMOTE_HASH_RUN_AS_ROOT" = "UNSET" ] || \
	   [ "$$REMOTE_HASH_INSTALL_CERT" = "UNSET" ] || \
	   [ "$$REMOTE_HASH_RESET_ROUTER" = "UNSET" ]; then \
		echo "❌ router-bootstrap: missing one or more HASH_* tags in remote output"; \
		printf "%s\n" "$$REMOTE_DATA"; \
		exit 1; \
	fi; \
	\
	# Step 3: fix known-hosts if missing \
	if [ "$$REMOTE_KNOWN_HOST" = "MISSING" ]; then \
		echo "🔑 Adding NAS host key to router root context" ; \
		NAS_KEY_LINES="$$(ssh-keyscan -p $(NAS_SSH_PORT) $(LAN_NAS) 2>/dev/null)" ; \
		if [ -z "$$NAS_KEY_LINES" ]; then \
			echo "❌ Failed to obtain NAS host key via ssh-keyscan" ; \
			exit 1 ; \
		fi ; \
		printf "%s\n" "$$NAS_KEY_LINES" | while IFS= read -r line; do \
			ssh $(SSH_HOST_ROUTER) "\
				touch /root/.ssh/known_hosts && \
				chmod 600 /root/.ssh/known_hosts && \
				grep -Fqx \"$$line\" /root/.ssh/known_hosts || echo \"$$line\" >> /root/.ssh/known_hosts \
			"; \
		done ; \
	fi ; \
	\
	# Step 4: compare hashes cleanly via exact variable matches \
	if [ "$$REMOTE_HASH_RUN_AS_ROOT" = "$$LOCAL_HASH_RUN_AS_ROOT" ] && \
	   [ "$$REMOTE_HASH_INSTALL_CERT" = "$$LOCAL_HASH_INSTALL_CERT" ] && \
	   [ "$$REMOTE_HASH_RESET_ROUTER" = "$$LOCAL_HASH_RESET_ROUTER" ] ; then \
		echo "🟢 Bootstrap primitives already up-to-date" ; \
		exit 0 ; \
	else \
		# Step 5: slow path — stream all three \
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
		echo "✅ Router primitives installed"; \
	fi

# ------------------------------------------------------------
# ROUTER BOOTSTRAP (PRIMITIVE)
# ------------------------------------------------------------
.PHONY: router-bootstrap
router-bootstrap: export ROUTER_BOOTSTRAP=1
router-bootstrap: \
	router-install-scripts \
	ensure-host-default-route \
	ensure-router-ula \
	router-provision-nvram \
	router-dhcp-range-ensure \
	router-dhcp-static-ensure \
	router-dnsmasq-sync \
	install-ssh-config \
	router-ddns \
	router-nat-install \
	router-ssh-invariants \
	router-disable-asus-ca
	@echo "🛠️ Router bootstrap complete — all base services provisioned"

.PHONY: ensure-runtime-dir
ensure-runtime-dir:
	@mkdir -p "$(RUNTIME_DIR)"

.PHONY: ensure-router-ula
ensure-router-ula: ensure-runtime-dir secrets-ready router-bootstrap-primitives | $(INSTALL_FILES_IF_CHANGED)
	@echo "🔧 Ensuring router ULA ($(ROUTER_ULA_VALUE))"

	$(call TMPFILE_BLOCK,"$(TMP_ROUTER_ULA)", \
		$(call WITH_SECRETS, sh -c '\
			TMPFILE="$(TMP_ROUTER_ULA)"; \
			printf "%s\n" "$(ROUTER_ULA_VALUE)" > "$$TMPFILE"; \
			\
			env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
				$(INSTALL_FILE_IF_CHANGED) \
					"" "" "$$TMPFILE" \
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

#ROUTER_SCRIPT_FILES := $(shell ls $(REPO_ROOT)/router/jffs/scripts/ | sort -u)
ROUTER_SCRIPT_FILES := $(wildcard $(REPO_ROOT)/router/jffs/scripts/* | sort -u)

.PHONY: router-install-%
router-install-%: | router-bootstrap-primitives
		@src="$(REPO_ROOT)/router/jffs/scripts/$*"; \
		if [ ! -f "$$src" ]; then \
			echo "⚠️ Skipping $* — source $$src not found"; \
		else \
			env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
				$(INSTALL_FILES_IF_CHANGED) -q \
					"$$src" "$(ROUTER_SCRIPTS)/$*" \
					$$ROUTER_ADDR $$ROUTER_SSH_PORT \
					$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE); \
		fi

ROUTER_IFC_MODE ?= vector

.PHONY: router-install-scripts
router-install-scripts: install-ssh-config \
	ensure-router-known-hosts router-scripts-invariants \
	$(INSTALL_FILE_IF_CHANGED) $(INSTALL_FILES_IF_CHANGED) \
	| repo-preflight ensure-router-ula
	@echo "🔍 Router script converge ($(ROUTER_IFC_MODE), deterministic)";
	@set -e; \
	case "$(ROUTER_IFC_MODE)" in \
		vector) \
			echo "➡️  Using $(INSTALL_FILES_IF_CHANGED) (portable, zero-bootstrap)"; \
			set --; \
			for f in $(ROUTER_SCRIPT_FILES); do \
			# f is already a full path (from ROUTER_SCRIPT_FILES) \
			src="$$f"; \
			dst="$(ROUTER_SCRIPTS)/$$(basename $$f)"; \
			if [ ! -f "$$src" ]; then \
				echo "⚠️ Skipping $$f — source $$src not found"; \
				continue; \
			fi; \
			# Append one full 9-arg tuple: \
			# SRC_HOST SRC_PORT SRC_PATH DST_HOST DST_PORT DST_PATH OWNER GROUP MODE \
			set -- "$$@" "" "" "$$src" "$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "$$dst" "$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "$(ROUTER_SCRIPTS_MODE)"; \
			done; \
			CHANGED=0; \
			rc=0; \
			$(INSTALL_FILES_IF_CHANGED) CHANGED "$$@" || rc=$$?; \
			if [ "$$rc" -eq 3 ]; then \
			echo "📝 Router scripts updated ($(ROUTER_IFC_MODE), deterministic)"; \
			elif [ "$$rc" -eq 0 ]; then \
			echo "🟢 Router scripts already up-to-date ($(ROUTER_IFC_MODE), deterministic)"; \
			else \
			echo "❌ Router scripts could not be installed (rc=$$rc) ($(ROUTER_IFC_MODE), deterministic)"; \
			exit $$rc; \
			fi \
			;; \
	  *) \
		echo "➡️  Using $(INSTALL_FILE_IF_CHANGED) (portable, zero-bootstrap)"; \
		for f in $(ROUTER_SCRIPT_FILES); do \
		  src="$$f"; \
		  dst="$(ROUTER_SCRIPTS)/$$(basename $$f)"; \
		  if [ ! -f "$$src" ]; then \
			echo "⚠️ Skipping $$f — source $$src not found"; \
			continue; \
		  fi; \
		  rc=0; \
		  $(INSTALL_FILE_IF_CHANGED) -q \
			"" "" "$$src" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "$$dst" \
			"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "$(ROUTER_SCRIPTS_MODE)" \
		  || rc=$$?; \
		  if [ "$$rc" -eq 3 ]; then \
			echo "📝 Router script updated $$dst ($(ROUTER_IFC_MODE), deterministic)"; \
		  elif [ "$$rc" -eq 0 ]; then \
			echo "🟢 Router script already up-to-date: $$dst ($(ROUTER_IFC_MODE), deterministic)"; \
		  else \
			echo "❌ Router scripts could not be installed $$f (rc=$$rc) ($(ROUTER_IFC_MODE), deterministic)"; \
			exit $$rc; \
		  fi; \
		done \
		;; \
	esac; \
	echo "🟢 All router scripts processed"

.PHONY: router-scripts-invariants
router-scripts-invariants: | router-ssh-check
	@echo "🛡️ Enforcing /jffs/scripts invariants + WAN bootstrap if IPv4 route missing"

	@ssh $(SSH_HOST_ROUTER) '\
		set -e; \
		\
		# --- WAN bootstrap: ensure IPv4 default route exists --- \
		if ! ip route show default | grep -q "dev eth0"; then \
			echo "⚠️  No IPv4 default route — triggering wan-event bootstrap"; \
			sh /jffs/scripts/wan-event 0 connected; \
		else \
			echo "🟢 IPv4 default route already present"; \
		fi; \
		\
		# --- Script ownership + permissions invariants --- \
		if [ -d /jffs/scripts ]; then \
			/jffs/scripts/run-as-root chown -R julie:root /jffs/scripts; \
			\
			# Hook scripts (executed by AsusWRT) ➡️ 755 \
			for f in services-start firewall-start wan-event dnsmasq-ready.sh wg-firewall.sh; do \
				if [ -f /jffs/scripts/$$f ]; then \
					/jffs/scripts/run-as-root chmod 755 /jffs/scripts/$$f; \
				fi; \
			done; \
			\
			# Control-plane scripts ➡️ 700 \
			for f in ipv6-watchdog.sh wan-reset.sh common.sh homelab-prefix-watchdog.sh; do \
				if [ -f /jffs/scripts/$$f ]; then \
					/jffs/scripts/run-as-root chmod 700 /jffs/scripts/$$f; \
				fi; \
			done; \
			\
			# State files ➡️ 600 \
			for f in .ipv6_watchdog_state dhcp6c-state; do \
				if [ -f /jffs/scripts/$$f ]; then \
					/jffs/scripts/run-as-root chmod 600 /jffs/scripts/$$f; \
				fi; \
			done; \
		fi; \
		\
		echo "🟢 /jffs/scripts invariants enforced"; \
	'

# Ensure runtime directory exists
$(RUNTIME_DIR)/homelab:
	@mkdir -p "$@"

print-ROUTER_SCRIPT_FILES:
	@printf '%q\n' $(ROUTER_SCRIPT_FILES)
print-ROUTER_SCRIPTS_OWNER:
	@echo 'OWNER="$(ROUTER_SCRIPTS_OWNER)"'

print-ROUTER_SCRIPTS_GROUP:
	@echo 'GROUP="$(ROUTER_SCRIPTS_GROUP)"'

print-ROUTER_SCRIPTS_MODE:
	@echo 'MODE="$(ROUTER_SCRIPTS_MODE)"'
