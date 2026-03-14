# ============================================================
# mk/10_groups.mk — Hardened group membership enforcement
# ============================================================

AUTHORIZED_ADMINS := julie

# Groups humans are allowed to be members of
ADMIN_GROUPS := systemd-journal docker sudo adm dnscrypt

# Groups owned exclusively by system services
SERVICE_GROUPS := headscale _dnsdist ssl-cert dnswarm

# Service accounts (User:PrimaryGroup)
# Format as user:group to make the relationship explicit
SERVICE_MAP := headscale:headscale _dnsdist:_dnsdist dnswarm:dnswarm

CURRENT_USER := $(shell id -un)

# ------------------------------------------------------------
# Verification (Read-Only)
# ------------------------------------------------------------
.PHONY: groups-compliant harden-groups
groups-compliant:
	@for g in $(ADMIN_GROUPS) $(SERVICE_GROUPS); do \
		getent group $$g >/dev/null 2>&1 || { echo "❌ Missing group: $$g"; exit 1; }; \
	done
	@for u in $(AUTHORIZED_ADMINS); do \
		id -u $$u >/dev/null 2>&1 || continue; \
		for g in $(ADMIN_GROUPS); do \
			id -nG $$u | grep -qw $$g || { echo "❌ $$u missing group $$g"; exit 1; }; \
		done; \
	done
	@for pair in $(SERVICE_MAP); do \
		u=$${pair%%:*}; \
		id -u $$u >/dev/null 2>&1 || { echo "❌ Missing service user: $$u"; exit 1; }; \
	done

harden-groups: ensure-run-as-root groups-compliant
	@echo "✅ Groups already compliant"

# ------------------------------------------------------------
# Authorization Guard (Re-usable)
# ------------------------------------------------------------
.PHONY: ensure-authorized-admin
ensure-authorized-admin:
	@echo "$(AUTHORIZED_ADMINS)" | grep -qw "$(CURRENT_USER)" || \
		{ echo "❌ User $(CURRENT_USER) not authorized for this mutation"; exit 1; }

# ------------------------------------------------------------
# Mutation Logic
# ------------------------------------------------------------
.PHONY: enforce-groups _enforce-groups
enforce-groups: ensure-authorized-admin ensure-run-as-root _enforce-groups
	@echo "✅ Group enforcement complete"

_enforce-groups:
	@for g in $(ADMIN_GROUPS) $(SERVICE_GROUPS); do \
		getent group $$g >/dev/null 2>&1 || { echo "➕ Creating group $$g"; $(run_as_root) groupadd --system $$g; }; \
	done
	@for u in $(AUTHORIZED_ADMINS); do \
		id -u $$u >/dev/null 2>&1 || { echo "⚠️ Admin $$u not found"; continue; }; \
		for g in $(ADMIN_GROUPS); do \
			id -nG $$u | grep -qw $$g || { echo "➕ Adding $$u to $$g"; $(run_as_root) usermod -aG $$g $$u; }; \
		done; \
	done
	@for pair in $(SERVICE_MAP); do \
		u=$${pair%%:*}; g=$${pair#*:}; \
		id -u $$u >/dev/null 2>&1 || { \
			echo "➕ Creating service user $$u ($$g)"; \
			$(run_as_root) useradd --system --gid $$g --shell /usr/sbin/nologin --home /nonexistent $$u; \
		}; \
	done

# ------------------------------------------------------------
# SSH Known Hosts
# ------------------------------------------------------------
KNOWN_HOSTS_SCRIPT_DST := $(INSTALL_PATH)/enforce_known_hosts.sh

.PHONY: enforce-known-hosts
enforce-known-hosts: ensure-authorized-admin ensure-run-as-root
	@$(call install_file,scripts/enforce_known_hosts.sh,$(KNOWN_HOSTS_SCRIPT_DST),root,root,0755)
	@for u in $(AUTHORIZED_ADMINS); do \
		homedir=$$(getent passwd $$u | cut -d: -f6); \
		[ -z "$$homedir" ] && continue; \
		echo "🔧 Enforcing known_hosts for $$u ($$homedir)"; \
		sudo -u $$u HOME="$$homedir" bash $(KNOWN_HOSTS_SCRIPT_DST); \
	done