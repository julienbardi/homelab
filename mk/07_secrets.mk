# mk/07_secrets.mk
# ============================================================================
# Secret Management: SOPS/Age Decryption Orchestration
# RAM-only, no decrypted files on disk
# ============================================================================

# ----------------------------------------------------------------------------
# 0. RAM-only workspace (per-user)
# ----------------------------------------------------------------------------

HOMELAB_RUNTIME_BASE := /run/user/$(shell id -u)/homelab
HOMELAB_RUNTIME_USER := $(HOMELAB_RUNTIME_BASE)

# Per-user secrets tmp dir (RAM-only)
export SECRETS_TMP_DIR := $(HOMELAB_RUNTIME_USER)/secrets/tmp

export SECRETS_LOCK := $(HOMELAB_RUNTIME_USER)/secrets/lock
export SECRETS_LOCK_PID := $(SECRETS_LOCK)/pid
export SECRETS_LOCK_TS  := $(SECRETS_LOCK)/ts

# Lock expires after N seconds
SECRETS_LOCK_MAX_AGE := 30

# Call as: $(call WITH_SECRETS, <shell commands>)
# Secrest are scoped to a subshell - they do NOT leak into the parent recipe
# environment or subsequent make recipe lines.
define WITH_SECRETS
	( \
		SECS="$$( $(SOPS_BIN) -d "$(SECRETS_FILE)" | $(YQ) -r 'to_entries | .[] | "\(.key)=\(.value)"' )"; \
		export $$SECS; \
		$(1) \
	)
endef


# ----------------------------------------------------------------------------
# DHCP static lease aggregation (non-secret, derived from secrets)
# ----------------------------------------------------------------------------
define LOAD_STATIC_DHCP
STATIC_DHCP="$$( $(call WITH_SECRETS, sh -c 'for v in $$(compgen -A variable | grep "^dhcp_static_"); do printf "%s " "$${!v}"; done') )"; export STATIC_DHCP
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
	@$(SOPS_BIN) -d "$(SECRETS_FILE)" \
		| awk -F': ' '/: / {gsub(/"/, "", $$2); printf "%s=\"%s\"\n", $$1, $$2}'

.PHONY: secrets-verify
secrets-verify: $(YQ_STAMP)
	@echo "🔎 Verifying secrets integrity"
	@echo "  • Checking encrypted file exists..."
	@if [ ! -f "$(SECRETS_FILE)" ]; then \
		echo "❌ Missing: $(SECRETS_FILE)"; \
		echo "👉 To initialize a new encrypted secrets file:"; \
		echo "   SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) $(SOPS_BIN) $(SECRETS_FILE)"; \
		exit 1; \
	fi
	@echo "  • Checking SOPS decryption..."
	@$(SOPS_BIN) -d "$(SECRETS_FILE)" >/dev/null || { echo "❌ Decryption failed"; exit 1; }
	@echo "  • Checking YAML structure..."
	@$(SOPS_BIN) -d "$(SECRETS_FILE)" \
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
		TMPDIR="$(SECRETS_TMP_DIR)" $(SOPS_BIN) "$(SECRETS_FILE)" || status=$$?; \
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
	@$(call WITH_SECRETS, sh -c '\
		if [ -n "$$VERBOSE" ] && [ "$$VERBOSE" != "0" ]; then \
			echo "Secrets OK (router_addr=$$ROUTER_ADDR)"; \
		fi \
	') || true

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

define WITH_SECRETS_v2
	( export $$($(SOPS_BIN) -d "$(SECRETS_FILE)" \
		| awk -F': ' '/: / {gsub(/"/, "", $$2); printf "%s=%q\n", $$1, $$2}'); \
	$(1) )
endef

# Ensure per-user runtime secrets workspace exists (RAM-only, managed by systemd)
.PHONY: secrets-runtime-init
secrets-runtime-init:
	@mkdir -p \
		"$(HOMELAB_RUNTIME_USER)/secrets" \
		"$(SECRETS_TMP_DIR)" \
		"$(HOMELAB_RUNTIME_USER)/ddns"

DDNS_ENV_FILE := /etc/homelab/ddns.env

.PHONY: ddns-env
ddns-env: secrets-runtime-init $(YQ_STAMP)
	@{ \
		# Export only NON-SECRET variables so run-as-root preserves them
		export SOPS_BIN="$(SOPS_BIN)"; \
		export SECRETS_FILE="$(SECRETS_FILE)"; \
		export YQ="$(YQ)"; \
		\
		$(run_as_root) bash -euo pipefail -c '\
			tmp="$$(mktemp)"; \
			trap "rm -f \"$$tmp\"" EXIT; \
			umask 077; \
			\
			eval "$$( \
				"$$SOPS_BIN" -d "$$SECRETS_FILE" \
				| "$$YQ" -r '\'' \
					"INFOMANIAK_API_KEY=\(.infomaniak_api_key)", \
					"INFOMANIAK_API_SECRET=\(.infomaniak_api_secret)" \
				'\'' \
			)"; \
			\
			printf "%s\n" \
				"INFOMANIAK_API_KEY=$$INFOMANIAK_API_KEY" \
				"INFOMANIAK_API_SECRET=$$INFOMANIAK_API_SECRET" \
				> "$$tmp"; \
			\
			install -m 600 -o $(ROOT_UID) -g $(ROOT_GID) "$$tmp" "$(DDNS_ENV_FILE)";
		'; \
		echo "🔐 Updated $(DDNS_ENV_FILE)"; \
	}

DDNS_RUNTIME_FILE := $(HOMELAB_RUNTIME_USER)/ddns/ddns.conf
# Contract: root-owned, RAM-only, consumed by DDNS updater

.PHONY: ddns-runtime
ddns-runtime: $(YQ_STAMP) secrets-runtime-init
	@{ \
		export SOPS_BIN="$(SOPS_BIN)"; \
		export SECRETS_FILE="$(SECRETS_FILE)"; \
		export YQ="$(YQ)"; \
		\
		$(run_as_root) bash -euo pipefail -c '\
			tmp="$$(mktemp)"; \
			trap "rm -f \"$$tmp\"" EXIT; \
			umask 077; \
			\
			eval "$$( \
				"$$SOPS_BIN" -d "$$SECRETS_FILE" \
				| "$$YQ" -r '\'' \
					"ddns_username=\(.ddns_username)", \
					"ddns_password=\(.ddns_password)", \
					"ddns_topdomain=\(.ddns_topdomain)" \
				'\'' \
			)"; \
			\
			printf "%s\n" \
				"ddns_username=$$ddns_username" \
				"ddns_password=$$ddns_password" \
				"ddns_topdomain=$$ddns_topdomain" \
				> "$$tmp"; \
			\
			install -m 600 -o $(ROOT_UID) -g $(ROOT_GID) "$$tmp" "$(DDNS_RUNTIME_FILE)"; \
		'; \
		echo "🔐 DDNS runtime file updated: $(DDNS_RUNTIME_FILE)"; \
	}

.PHONY: test-infomaniak-token
test-infomaniak-token:
	@$(call WITH_SECRETS, printf "INFOMANIAK_API_TOKEN=%s\n" "$$INFOMANIAK_API_TOKEN")

.PHONY: test-infomaniak-dns-api
test-infomaniak-dns-api:
	@$(call WITH_SECRETS, \
		curl -s -o /dev/null -w "HTTP=%{http_code}\n" \
			-H "Authorization: Bearer $$INFOMANIAK_API_TOKEN" \
			https://api.infomaniak.com/2/domains/domains \
	)

.PHONY: test-infomaniak-txt-dryrun
test-infomaniak-txt-dryrun:
	@$(call WITH_SECRETS, \
		domain="bardi.ch"; \
		name="_acme-challenge.dryrun"; \
		value="homelab-dryrun-$$RANDOM"; \
		echo "🟦 Creating TXT: $$name → $$value"; \
		resp=$$(curl -s -X POST \
			-H "Authorization: Bearer $$INFOMANIAK_API_TOKEN" \
			-H "Content-Type: application/json" \
			-d "{\"type\":\"TXT\",\"name\":\"$$name\",\"target\":\"$$value\",\"ttl\":60}" \
			"https://api.infomaniak.com/2/domains/domains/$$domain/records"); \
		echo "$$resp" | grep -q '"id"' || { echo "❌ TXT create failed"; echo "$$resp"; exit 1; }; \
		rec_id=$$(echo "$$resp" | sed -n 's/.*\"id\":[ ]*\([0-9]*\).*/\1/p'); \
		echo "🟢 Created TXT record id=$$rec_id"; \
		echo "🟦 Deleting TXT id=$$rec_id"; \
		curl -s -X DELETE \
			-H "Authorization: Bearer $$INFOMANIAK_API_TOKEN" \
			"https://api.infomaniak.com/2/domains/domains/$$domain/records/$$rec_id" >/dev/null; \
		echo "🟢 Deleted TXT record"; \
	)
