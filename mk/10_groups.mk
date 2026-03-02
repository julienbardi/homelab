# ============================================================
# mk/10_groups.mk
# ------------------------------------------------------------
# Hardened group membership enforcement
#
# Contracts:
# - harden-groups: verify invariants only (safe under sudo)
# - enforce-groups: mutate state to satisfy invariants
#                   (authorized human only)
# ============================================================

# Users part of the admin group
AUTHORIZED_ADMINS = julie

# Groups that humans are allowed to be members of
ADMIN_GROUPS = \
	systemd-journal \
	docker \
	sudo \
	adm \
	dnscrypt

# Groups owned exclusively by system services
SERVICE_GROUPS = \
	headscale \
	_dnsdist \
	ssl-cert \
	dnswarm

# Service accounts to create (one per service group)
# On Debian systems, ssl-cert is usually group-only, not a user.
SERVICE_USERS = headscale _dnsdist dnswarm

CURRENT_USER := $(shell id -un)

# ------------------------------------------------------------
# Verification-only: exits non-zero on any drift
# ------------------------------------------------------------
.PHONY: groups-compliant
groups-compliant:
	@for g in $(ADMIN_GROUPS); do \
		getent group $$g >/dev/null 2>&1 || { echo "❌ Missing admin group: $$g. Run 'make enforce-groups' to fix."; exit 1; }; \
		for u in $(AUTHORIZED_ADMINS); do \
			id -u $$u >/dev/null 2>&1 || continue; \
			id -nG $$u | grep -qw $$g || { echo "❌ $$u not in $$g. Run 'make enforce-groups' to fix."; exit 1; }; \
		done; \
		for u in $$(getent group $$g | awk -F: '{print $$4}' | tr ',' ' '); do \
			[ -z "$$u" ] && continue; \
			case " $(AUTHORIZED_ADMINS) " in \
				*" $$u "*) ;; \
				*) echo "❌ Unauthorized member $$u in $$g. Run 'make enforce-groups' to fix."; exit 1 ;; \
			esac; \
		done; \
	done; \
	for g in $(SERVICE_GROUPS); do \
		getent group $$g >/dev/null 2>&1 || { echo "❌ Missing service group: $$g. Run 'make enforce-groups' to fix."; exit 1; }; \
	done; \
	for u in $(SERVICE_USERS); do \
		id -u $$u >/dev/null 2>&1 || { echo "❌ Missing service user: $$u. Run 'make enforce-groups' to fix."; exit 1; }; \
	done

# ------------------------------------------------------------
# Public target used by converge: verify only, never mutates
# ------------------------------------------------------------
.PHONY: harden-groups
harden-groups: ensure-run-as-root groups-compliant
	@echo "✅ Groups already compliant"

# ------------------------------------------------------------
# Authorization guard (human-gated)
# ------------------------------------------------------------
.PHONY: ensure-authorized-admin
ensure-authorized-admin:
	@if ! echo "$(AUTHORIZED_ADMINS)" | grep -qw "$(CURRENT_USER)"; then \
		echo "❌ Current user $(CURRENT_USER) is not authorized to enforce groups"; \
		exit 1; \
	fi

# ------------------------------------------------------------
# Mutation entrypoint (explicit, declarative)
# ------------------------------------------------------------
.PHONY: enforce-groups
enforce-groups: ensure-authorized-admin ensure-run-as-root _enforce-groups
	@echo "✅ Group enforcement complete"

# ------------------------------------------------------------
# Mutation logic (unchanged, authoritative)
# ------------------------------------------------------------
.PHONY: _enforce-groups
_enforce-groups: ensure-run-as-root
	@missing=""; \
	for u in $(AUTHORIZED_ADMINS); do \
		if ! id -u $$u >/dev/null 2>&1; then \
			$(call log,⚠️ User $$u does not exist, skipping admin membership); \
			missing="$$missing $$u"; \
		fi; \
	done; \
	for g in $(ADMIN_GROUPS); do \
		if ! getent group $$g >/dev/null 2>&1; then \
			$(call log,➕ Creating admin group $$g); \
			$(run_as_root) groupadd $$g; \
		fi; \
		for u in $(AUTHORIZED_ADMINS); do \
			case " $$missing " in *" $$u "*) continue ;; esac; \
			if ! id -nG $$u | grep -qw $$g; then \
				$(call log,➕ Adding user $$u to group $$g); \
				$(run_as_root) usermod -aG $$g $$u; \
			fi; \
		done; \
		for u in $$(getent group $$g | awk -F: '{print $$4}' | tr ',' ' '); do \
			[ -z "$$u" ] && continue; \
			case " $(AUTHORIZED_ADMINS) " in \
				*" $$u "*) ;; \
				*) $(call log,❌ Removing user $$u from group $$g (not authorized)); \
				   $(run_as_root) gpasswd -d $$u $$g || true ;; \
			esac; \
		done; \
		echo "🎯 Admin group $$g enforced"; \
	done; \
	for g in $(SERVICE_GROUPS); do \
		if ! getent group $$g >/dev/null 2>&1; then \
			$(call log,➕ Creating service group $$g); \
			$(run_as_root) groupadd --system $$g; \
		fi; \
		echo "🎯 Service group $$g ensured"; \
	done; \
	for u in $(SERVICE_USERS); do \
		if ! id -u $$u >/dev/null 2>&1; then \
			$(call log,➕ Creating service user $$u with primary group $$u); \
			$(run_as_root) useradd --system --gid $$u --shell /usr/sbin/nologin --home /nonexistent $$u; \
		fi; \
	done

# ------------------------------------------------------------
# Inspection helper
# ------------------------------------------------------------
.PHONY: check-groups
check-groups:
	@for g in $(ADMIN_GROUPS) $(SERVICE_GROUPS); do \
		if getent group $$g >/dev/null 2>&1; then \
			echo "🔎 Members of $$g:"; \
			getent group $$g | awk -F: '{print $$4}' | tr ',' ' '; \
		else \
			$(call log,⚠️ Group $$g does not exist); \
		fi; \
	done

# ============================================================
# Install SSH known_hosts enforcement script prerequisite
# ------------------------------------------------------------

KNOWN_HOSTS_SCRIPT_SRC := $(MAKEFILE_DIR)scripts/enforce_known_hosts.sh
KNOWN_HOSTS_SCRIPT_DST := $(INSTALL_PATH)/enforce_known_hosts.sh
KNOWN_HOSTS_SCRIPT_OWNER := root
KNOWN_HOSTS_SCRIPT_GROUP := root
KNOWN_HOSTS_SCRIPT_MODE := 0755

.PHONY: prereqs-enforce-known-hosts-script
prereqs-enforce-known-hosts-script:
	@$(INSTALL_PATH)/atomic_install "$(KNOWN_HOSTS_SCRIPT_SRC)" "$(KNOWN_HOSTS_SCRIPT_DST)" "$(KNOWN_HOSTS_SCRIPT_OWNER):$(KNOWN_HOSTS_SCRIPT_GROUP)" "$(KNOWN_HOSTS_SCRIPT_MODE)"

# ============================================================
# SSH known_hosts enforcement
# ------------------------------------------------------------

.PHONY: enforce-known-hosts
enforce-known-hosts: prereqs-enforce-known-hosts-script ensure-authorized-admin-known-hosts ensure-run-as-root _enforce-known-hosts
	@echo "✅ SSH known_hosts enforcement complete"

.PHONY: _enforce-known-hosts
_enforce-known-hosts:
	@for u in $(AUTHORIZED_ADMINS); do \
		homedir=$$(sudo -u $$u bash -c 'echo $$HOME'); \
		echo "🔧 Running known_hosts enforcement for user $$u"; \
		sudo -u $$u HOME="$$homedir" bash $(KNOWN_HOSTS_SCRIPT_DST); \
	done

.PHONY: ensure-authorized-admin-known-hosts
ensure-authorized-admin-known-hosts:
	@if ! echo "$(AUTHORIZED_ADMINS)" | grep -qw "$(CURRENT_USER)"; then \
		echo "❌ Current user $(CURRENT_USER) is not authorized to enforce known_hosts"; \
		exit 1; \
	fi
