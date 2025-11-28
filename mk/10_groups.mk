# ============================================================
# mk/groups.mk
# ------------------------------------------------------------
# Hardened group membership enforcement
# Provides a generic macro `enforce-group` and specific targets
# for sensitive groups. Each target documents its intent.
# ============================================================

# Generic macro: enforce membership for TARGET_GROUP
# Usage:
#   make enforce-group TARGET_GROUP=systemd-journal AUTHORIZED_USERS="$(AUTHORIZED_ADMINS)"
# mk/groups.mk
AUTHORIZED_ADMINS = julie leona
SENSITIVE_GROUPS = systemd-journal docker sudo adm sshusers

# Harden all groups in one go
harden-groups:
	@missing=""
	@for u in $(AUTHORIZED_ADMINS); do \
		if ! id -u $$u >/dev/null 2>&1; then \
			$(call log, ⚠️ User $$u does not exist, skipping all groups); \
			missing="$$missing $$u"; \
		fi; \
	done; \
	for g in $(SENSITIVE_GROUPS); do \
		if ! getent group $$g >/dev/null 2>&1; then \
			$(call log, ⚠️ Group $$g does not exist, skipping enforcement); \
			continue; \
		fi; \
		for u in $(AUTHORIZED_ADMINS); do \
			case " $$missing " in *" $$u "*) continue ;; esac; \
			if ! id -nG $$u | grep -qw $$g; then \
				$(call log, ➕ Adding user $$u to group $$g); \
				sudo usermod -aG $$g $$u; \
			fi; \
		done; \
		for u in $$(getent group $$g | awk -F: '{print $$4}' | tr ',' ' '); do \
			case " $(AUTHORIZED_ADMINS) " in \
				*" $$u "*) ;; \
				*) $(call log, ❌ Removing user $$u from group $$g (not authorized)); \
				   sudo gpasswd -d $$u $$g || true ;; \
			esac; \
		done; \
		echo "🎯 Group $$g membership enforced"; \
	done

check-groups:
	@for g in $(SENSITIVE_GROUPS); do \
		if getent group $$g >/dev/null 2>&1; then \
			echo "🔎 Current members of $$g:"; \
			getent group $$g | awk -F: '{print $$4}' | tr ',' ' '; \
		else \
			$(call log, ⚠️ Group $$g does not exist); \
		fi; \
	done
