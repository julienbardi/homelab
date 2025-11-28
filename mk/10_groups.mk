# ============================================================
# mk/groups.mk
# ------------------------------------------------------------
# Hardened group membership enforcement
# Provides a generic macro `enforce-group` and specific targets
# for sensitive groups. Each target documents its intent.
# ============================================================

AUTHORIZED_ADMINS = julie leona

# Generic macro: enforce membership for TARGET_GROUP
# Usage:
#   make enforce-group TARGET_GROUP=systemd-journal AUTHORIZED_USERS="$(AUTHORIZED_ADMINS)"
enforce-group:
	@for u in $(AUTHORIZED_USERS); do \
		if id -u $$u >/dev/null 2>&1; then \
			if ! id -nG $$u | grep -qw $(TARGET_GROUP); then \
				log "➕ Adding user $$u to group $(TARGET_GROUP)"; \
				sudo usermod -aG $(TARGET_GROUP) $$u; \
			fi; \
		else \
			log "⚠️ User $$u does not exist, skipping"; \
		fi; \
	done; \
	for u in $$(getent group $(TARGET_GROUP) | awk -F: '{print $$4}' | tr ',' ' '); do \
		case " $(AUTHORIZED_USERS) " in \
			*" $$u "*) ;; \
			*) log "❌ Removing user $$u from group $(TARGET_GROUP) (not authorized)"; \
			   sudo gpasswd -d $$u $(TARGET_GROUP) || true ;; \
		esac; \
	done; \
	echo "🎯 Group $(TARGET_GROUP) membership enforced"

# ------------------------------------------------------------
# Specific group rules with intent
# ------------------------------------------------------------

# systemd-journal: who can read system logs (security-sensitive)
journal-access:
	$(MAKE) enforce-group TARGET_GROUP=systemd-journal AUTHORIZED_USERS="$(AUTHORIZED_ADMINS)"

# docker: who can run containers (root-equivalent privileges)
docker-access:
	$(MAKE) enforce-group TARGET_GROUP=docker AUTHORIZED_USERS="$(AUTHORIZED_ADMINS)"

# sudo: who can escalate privileges (critical security boundary)
sudo-access:
	$(MAKE) enforce-group TARGET_GROUP=sudo AUTHORIZED_USERS="$(AUTHORIZED_ADMINS)"

# adm: who can read system logs (legacy group, similar to systemd-journal)
adm-access:
	$(MAKE) enforce-group TARGET_GROUP=adm AUTHORIZED_USERS="$(AUTHORIZED_ADMINS)"

# sshusers: who can log in via SSH (custom group if maintained)
ssh-access:
	$(MAKE) enforce-group TARGET_GROUP=sshusers AUTHORIZED_USERS="$(AUTHORIZED_ADMINS)"

# Meta target: enforce all sensitive groups in one go
harden-groups: journal-access docker-access sudo-access adm-access ssh-access

# Optional: audit current membership without changes
check-groups:
	@for g in systemd-journal docker sudo adm sshusers; do \
		echo "🔎 Current members of $$g:"; \
		getent group $$g | awk -F: '{print $$4}' | tr ',' ' '; \
	done
