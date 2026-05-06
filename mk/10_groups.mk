# ============================================================
# mk/10_groups.mk — Hardened group membership enforcement
# ============================================================

.PHONY: enforce-groups
enforce-groups: ensure-authorized-admin ensure-run-as-root
	@# Ensure all admin + service groups exist
	@for g in $(ADMIN_GROUPS) $(SERVICE_GROUPS); do \
		getent group "$$g" >/dev/null 2>&1 || { \
			echo "📍 Creating group $$g"; \
			$(run_as_root) groupadd --system "$$g"; \
		}; \
	done

	@# Ensure all authorized admins belong to all admin groups
	@for u in $(AUTHORIZED_ADMINS); do \
		id -u "$$u" >/dev/null 2>&1 || { echo "⚠️ Admin $$u not found"; continue; }; \
		for g in $(ADMIN_GROUPS); do \
			id -nG "$$u" | grep -qw "$$g" || { \
				echo "📍 Adding $$u to $$g"; \
				$(run_as_root) usermod -aG "$$g" "$$u"; \
				echo "ℹ️ Group membership for $$u updated — start a new login session to apply."; \
			}; \
		done; \
	done

	@# Ensure authorized admins belong to ssl-cert for read-only TLS access
	@for u in $(AUTHORIZED_ADMINS); do \
		id -u "$$u" >/dev/null 2>&1 || { echo "⚠️ Admin $$u not found"; continue; }; \
		if echo "$(SERVICE_GROUPS)" | grep -qw "ssl-cert"; then \
			id -nG "$$u" | grep -qw "ssl-cert" || { \
				echo "📍 Adding $$u to ssl-cert"; \
				$(run_as_root) usermod -aG ssl-cert "$$u"; \
				echo "ℹ️ Group membership for $$u updated — start a new login session to apply."; \
			}; \
		fi; \
	done

	@# Ensure all service users + service groups exist
	@for pair in $(SERVICE_MAP); do \
		u=$${pair%%:*}; g=$${pair#*:}; \
		getent group "$$g" >/dev/null 2>&1 || { \
			echo "📍 Creating service group $$g"; \
			$(run_as_root) groupadd --system "$$g"; \
		}; \
		id -u "$$u" >/dev/null 2>&1 || { \
			echo "📍 Creating service user $$u ($$g)"; \
			$(run_as_root) useradd --system --gid "$$g" --shell /usr/sbin/nologin --home /nonexistent "$$u"; \
		}; \
	done

# ------------------------------------------------------------
# SSH Known Hosts Enforcement (Canonical & Idempotent)
# ------------------------------------------------------------
.PHONY: enforce-known-hosts
enforce-known-hosts: ensure-authorized-admin ensure-run-as-root
	@for u in $(AUTHORIZED_ADMINS); do \
		homedir=$$(getent passwd "$$u" | cut -d: -f6); \
		if [ -z "$$homedir" ] || [ ! -d "$$homedir" ]; then \
			echo "⚠️ No home for $$u"; \
			continue; \
		fi; \
		kh="$$homedir/.ssh/known_hosts"; \
		[ ! -d "$$homedir/.ssh" ] && { mkdir -p "$$homedir/.ssh"; chmod 700 "$$homedir/.ssh"; chown $$u: "$$homedir/.ssh"; }; \
		touch "$$kh"; chown $$u: "$$kh"; chmod 644 "$$kh"; \
		{ \
			flock -x 9; \
			for hp in $(KNOWN_HOSTS); do \
				host=$${hp%:*}; port=$${hp#*:}; \
				target="[$$host]:$$port"; \
				keyline=$$(ssh-keyscan -p "$$port" "$$host" 2>/dev/null || true); \
				if [ -z "$$keyline" ]; then \
					echo "❌ $$target unreachable"; \
					continue; \
				fi; \
				stored_fp=$$(ssh-keygen -F "$$target" -f "$$kh" 2>/dev/null | awk '/^#/{next} {print}' | ssh-keygen -lf - 2>/dev/null || true); \
				current_fp=$$(echo "$$keyline" | ssh-keygen -lf -); \
				if [ -z "$$stored_fp" ]; then \
					echo "📍 Adding new host key for $$target to $$u"; \
					echo "$$keyline" >> "$$kh"; \
				elif [ "$$stored_fp" != "$$current_fp" ]; then \
					echo "⚠️ Host key changed for $$target for $$u"; \
					ssh-keygen -R "$$target" -f "$$kh" >/dev/null 2>&1; \
					echo "$$keyline" >> "$$kh"; \
				fi; \
			done; \
		} 9>"$$kh.lock"; \
	done