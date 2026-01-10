# ============================================================
# mk/groups.mk
# ------------------------------------------------------------
# Hardened group membership enforcement
#
# - ADMIN_GROUPS: human-managed privilege groups
# - SERVICE_GROUPS: system service groups (no human members)
#
# This file enforces group existence and membership invariants
# in a Debian-compliant, upgrade-safe manner.
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
	coredns \
	_dnsdist

# Service accounts to create (one per service group)
SERVICE_USERS = $(SERVICE_GROUPS)

# Guard: only allow authorized admins to run these targets
CURRENT_USER := $(shell id -un)

# ------------------------------------------------------------
# Harden all groups in one go
# ------------------------------------------------------------
harden-groups: ensure-run-as-root
	@if ! echo "$(AUTHORIZED_ADMINS)" | grep -qw "$(CURRENT_USER)"; then \
		echo "❌ Current user $(CURRENT_USER) is not authorized to enforce groups"; \
		exit 1; \
	fi

	@missing=""
	@for u in $(AUTHORIZED_ADMINS); do \
		if ! id -u $$u >/dev/null 2>&1; then \
			$(call log,⚠️ User $$u does not exist, skipping admin membership); \
			missing="$$missing $$u"; \
		fi; \
	done

	@for g in $(ADMIN_GROUPS); do \
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
			case " $(AUTHORIZED_ADMINS) " in \
				*" $$u "*) ;; \
				*) $(call log,❌ Removing user $$u from group $$g (not authorized)); \
				   $(run_as_root) gpasswd -d $$u $$g || true ;; \
			esac; \
		done; \
		echo "🎯 Admin group $$g enforced"; \
	done

	@for g in $(SERVICE_GROUPS); do \
		if ! getent group $$g >/dev/null 2>&1; then \
			$(call log,➕ Creating service group $$g); \
			$(run_as_root) groupadd --system $$g; \
		fi; \
		echo "🎯 Service group $$g ensured"; \
	done

	@for u in $(SERVICE_USERS); do \
		if ! id -u $$u >/dev/null 2>&1; then \
			$(call log,➕ Creating service user $$u with primary group $$u); \
			$(run_as_root) useradd --system --gid $$u --shell /usr/sbin/nologin --home /nonexistent $$u; \
		fi; \
	done

# ------------------------------------------------------------
# Inspection helper
# ------------------------------------------------------------
check-groups:
	@for g in $(ADMIN_GROUPS) $(SERVICE_GROUPS); do \
		if getent group $$g >/dev/null 2>&1; then \
			echo "🔎 Members of $$g:"; \
			getent group $$g | awk -F: '{print $$4}' | tr ',' ' '; \
		else \
			$(call log,⚠️ Group $$g does not exist); \
		fi; \
	done
