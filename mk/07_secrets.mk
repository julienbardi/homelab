# mk/07_secrets.mk
# ============================================================================
# Secret Management: SOPS/Age Decryption Orchestration
# RAM-only, no decrypted files on disk
# ============================================================================

# Ensure SOPS can decrypt inside Make recipes
export SOPS_AGE_KEY_FILE := /etc/sops/keys/age.key

SOPS             := /usr/local/bin/sops
export SECRETS_FILE  := $(REPO_ROOT)/secrets.enc.yaml

# ----------------------------------------------------------------------------
# 0. RAM-only workspace (per-user)
# ----------------------------------------------------------------------------

HOMELAB_RUNTIME_BASE := /run/user/$(shell id -u)/homelab
export HOMELAB_RUNTIME_USER := $(HOMELAB_RUNTIME_BASE)

# Per-user secrets tmp dir (RAM-only)
export SECRETS_TMP_DIR := $(HOMELAB_RUNTIME_USER)/secrets/tmp

# Ensure per-user runtime secrets workspace exists (RAM-only, managed by systemd)
$(shell mkdir -p $(HOMELAB_RUNTIME_USER)/secrets $(SECRETS_TMP_DIR))

export SECRETS_LOCK := $(HOMELAB_RUNTIME_USER)/secrets/lock
export SECRETS_LOCK_PID := $(SECRETS_LOCK)/pid
export SECRETS_LOCK_TS  := $(SECRETS_LOCK)/ts

# Lock expires after N seconds
SECRETS_LOCK_MAX_AGE := 30

# Call as: $(call WITH_SECRETS, <shell commands>)
define WITH_SECRETS
	export $$($(SOPS) -d $(REPO_ROOT)/secrets.enc.yaml \
		| awk -F': ' '/: / {gsub(/"/, "", $$2); print $$1 "=" $$2}'); \
	$(1)
endef

# ----------------------------------------------------------------------------
# DHCP static lease aggregation (non-secret, derived from secrets)
# ----------------------------------------------------------------------------
define LOAD_STATIC_DHCP
STATIC_DHCP="$$( $(WITH_SECRETS) sh -c 'for v in $$(compgen -A variable | grep "^dhcp_static_"); do printf "%s" "$${!v}"; done' )"; export STATIC_DHCP
endef

# ----------------------------------------------------------------------------
# 1. SOPS CONFIGURATION & GUARDS
# ----------------------------------------------------------------------------

.PHONY: sops-init
sops-init:
	@if [ ! -f ".sops.yaml" ] || ! grep -Fq "$(SOPS_AGE_PUBKEY)" ".sops.yaml"; then \
		echo "⚙️ Configuring .sops.yaml (Identity: $(SOPS_AGE_PUBKEY))..."; \
		printf "creation_rules:\n  - path_regex: $(SECRETS_FILE)$$\n    age: $(SOPS_AGE_PUBKEY)\n" > .sops.yaml; \
	fi

.PHONY: secrets-status
secrets-status:
	@echo "🔎 Secrets subsystem status"
	@echo "  USER: $(shell id -un)"
	@echo "  FILE: $(SECRETS_FILE)"
	@echo "  BASE: $(HOMELAB_RUNTIME_USER)/secrets"
	@echo ""
	@echo "🔒 Lock state:"
	@if [ -d "$(SECRETS_LOCK)" ]; then \
		echo "  LOCKED"; \
		[ -f "$(SECRETS_LOCK_PID)" ] && echo "  PID → $$(cat $(SECRETS_LOCK_PID))"; \
		[ -f "$(SECRETS_LOCK_TS)" ] && echo "  TS  → $$(cat $(SECRETS_LOCK_TS))"; \
	else \
		echo "  UNLOCKED"; \
	fi

.PHONY: secrets-break-lock
secrets-break-lock:
	@if [ ! -d "$(SECRETS_LOCK)" ]; then \
		echo "🔓 No lock present"; \
		exit 0; \
	fi
	@echo "⚠️ Breaking secrets lock manually"
	@rm -rf "$(SECRETS_LOCK)"
	@echo "🔓 Lock removed"

.PHONY: secrets-dump
secrets-dump:
	@echo "🔐 Dumping decrypted secrets (RAM-only):"
	@$(SOPS) -d "$(SECRETS_FILE)" \
		| awk -F': ' '/: / {gsub(/"/, "", $$2); printf "%s=\"%s\"\n", $$1, $$2}'

.PHONY: secrets-verify
secrets-verify: $(YQ_STAMP)
	@echo "🔎 Verifying secrets integrity"
	@echo "  • Checking encrypted file exists..."
	@if [ ! -f "$(SECRETS_FILE)" ]; then \
		echo "❌ Missing: $(SECRETS_FILE)"; \
		echo "👉 To initialize a new encrypted secrets file:"; \
		echo "   SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) $(SOPS) $(SECRETS_FILE)"; \
		exit 1; \
	fi
	@echo "  • Checking SOPS decryption..."
	@$(SOPS) -d "$(SECRETS_FILE)" >/dev/null || { echo "❌ Decryption failed"; exit 1; }
	@echo "  • Checking YAML structure..."
	@$(SOPS) -d "$(SECRETS_FILE)" \
		| $(YQ) e 'keys' - >/dev/null || { echo "❌ Invalid YAML"; exit 1; }
	@echo "🟢 Secrets OK — decryptable and structurally valid"


.PHONY: secrets-edit
secrets-edit:
	@{ \
		lock_dir="$(SECRETS_LOCK)"; \
		lock_ts="$(SECRETS_LOCK_TS)"; \
		now=$$(date +%s); \
		# Stale lock handling
		if [ -d "$$lock_dir" ]; then \
			if [ -f "$$lock_ts" ]; then \
				ts=$$(cat "$$lock_ts" 2>/dev/null || echo 0); \
				age=$$((now - ts)); \
				if [ $$age -gt $(SECRETS_LOCK_MAX_AGE) ]; then \
					echo "⚠️ Stale secrets lock detected (age $$age s > $(SECRETS_LOCK_MAX_AGE)s). Breaking it."; \
					rm -rf "$$lock_dir"; \
				fi; \
			else \
				echo "⚠️ Lock directory exists but no timestamp — breaking lock."; \
				rm -rf "$$lock_dir"; \
			fi; \
		fi; \
		# Acquire lock
		while ! mkdir "$$lock_dir" 2>/dev/null; do \
			echo "⏳ Waiting for secrets lock (use make secrets-break-lock to force-remove the lock) ..."; \
			sleep 0.1; \
		done; \
		echo $$now > "$$lock_ts"; \
		trap 'rm -rf "$$lock_dir" 2>/dev/null || true' EXIT; \
		echo "📝 Editing encrypted secrets with SOPS ($(SECRETS_FILE))"; \
		status=0; \
		TMPDIR="$(SECRETS_TMP_DIR)" $(SOPS) "$(SECRETS_FILE)" || status=$$?; \
		if [ $$status -eq 200 ]; then \
			status=0; \
		fi; \
		if [ $$status -ne 0 ]; then \
			echo "❌ SOPS error (exit $$status)"; \
			exit $$status; \
		fi; \
		true; \
	}

secrets-ready:
	@$(WITH_SECRETS) \
		{ [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && echo "Secrets OK (router_addr=$$router_addr)"; } || true

.PHONY: check-age-key
check-age-key: ensure-authorized-admin
	@echo "🔎 Checking system AGE key (/etc/sops/keys/age.key)"

	@{ \
		key="/etc/sops/keys/age.key"; \
		if [ ! -f "$$key" ]; then \
			echo "❌ AGE key missing at $$key"; \
			exit 1; \
		fi; \
		info="$$(stat -c '%a %U %G' "$$key" 2>/dev/null || echo MISSING)"; \
		if [ "$$info" != "640 root admin" ]; then \
			echo "⚠️  AGE key permissions drifted ($$info → fixing)"; \
			$(run_as_root) sh -c "chown root:admin \"$$key\" && chmod 640 \"$$key\""; \
			info="$$(stat -c '%a %U %G' "$$key")"; \
			echo "🛠️  Permissions set to $$info"; \
		fi; \
	}

	@if ! sudo -E -u "$(OPERATOR_USER)" sops -d "$(SECRETS_FILE)" >/dev/null 2>&1; then \
		echo "❌ AGE key exists but cannot decrypt $(SECRETS_FILE) as $(OPERATOR_USER)"; \
		exit 1; \
	fi

	@{ \
		pub="$$( $(run_as_root) age-keygen -y /etc/sops/keys/age.key 2>/dev/null )"; \
		if [ -z "$$pub" ]; then \
			echo "❌ AGE key is invalid or unreadable"; \
			exit 1; \
		fi; \
		echo "🟢 AGE key OK — ts=$$(stat -c '%y' /etc/sops/keys/age.key) pub=$$pub user=$(OPERATOR_USER)"; \
	}

