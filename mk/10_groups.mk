# ============================================================
# mk/10_groups.mk — Hardened group + user enforcement
# ============================================================

.PHONY: enforce-groups
enforce-groups:
	@# Ensure admin groups exist (non-system)
	@for g in $(ADMIN_GROUPS); do \
		getent group "$$g" >/dev/null || { \
			echo " Creating admin group $$g"; \
			$(run_as_root) groupadd "$$g"; \
		}; \
	done

	@# Ensure service groups exist (system)
	@for g in $(SERVICE_GROUPS); do \
		getent group "$$g" >/dev/null || { \
			echo " Creating service group $$g"; \
			$(run_as_root) groupadd --system "$$g"; \
		}; \
	done

	@# Ensure authorized admins exist and belong to admin groups
	@for u in $(AUTHORIZED_ADMINS); do \
		id -u "$$u" >/dev/null 2>&1 || { echo "⚠️ Admin $$u not found"; continue; }; \
		groups=$$(id -nG "$$u"); \
		for g in $(ADMIN_GROUPS); do \
			echo "$$groups" | grep -qw "$$g" || { \
				echo " Adding $$u to $$g"; \
				$(run_as_root) usermod -aG "$$g" "$$u"; \
				echo "ℹ️ $$u must re-login to apply group membership."; \
			}; \
		done; \
	done

	@# Ensure service users exist
	@for pair in $(SERVICE_MAP); do \
		u=$${pair%%:*}; g=$${pair#*:}; \
		getent group "$$g" >/dev/null || $(run_as_root) groupadd --system "$$g"; \
		id -u "$$u" >/dev/null 2>&1 || { \
			echo " Creating service user $$u ($$g)"; \
			$(run_as_root) useradd --system --gid "$$g" --shell /usr/sbin/nologin --home /nonexistent "$$u"; \
		}; \
	done

# ------------------------------------------------------------
# SSH Known Hosts Enforcement (Canonical & Idempotent)
# ------------------------------------------------------------
.PHONY: enforce-known-hosts
enforce-known-hosts:
	@for u in $(AUTHORIZED_ADMINS); do \
		homedir=$$(getent passwd "$$u" | cut -d: -f6); \
		if [ -z "$$homedir" ] || [ ! -d "$$homedir" ]; then \
			echo "⚠️ No home for $$u"; \
			continue; \
		fi; \
		kh="$$homedir/.ssh/known_hosts"; \
		[ ! -d "$$homedir/.ssh" ] && { mkdir -p "$$homedir/.ssh"; chmod 700 "$$homedir/.ssh"; chown "$$u":"$(id -gn "$$u")" "$$homedir/.ssh"; }; \
		touch "$$kh"; chown "$$u":"$(id -gn "$$u")" "$$kh"; chmod 644 "$$kh"; \
		{ \
			flock -xn 9 || { echo "⚠️ Lock busy for $$u, skipping"; continue; }; \
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
					echo " Adding new host key for $$target to $$u"; \
					echo "$$keyline" >> "$$kh"; \
				elif [ "$$stored_fp" != "$$current_fp" ]; then \
					echo "⚠️ Host key changed for $$target for $$u"; \
					ssh-keygen -R "$$target" -f "$$kh" >/dev/null 2>&1; \
					echo "$$keyline" >> "$$kh"; \
				fi; \
			done; \
		} 9>"$$kh.lock"; chmod 600 "$$kh.lock"; \
	done