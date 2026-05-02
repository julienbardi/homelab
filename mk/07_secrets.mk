# mk/07_secrets.mk
# ============================================================================
# Secret Management: SOPS/Age Decryption Orchestration
# RAM-only, content-addressed deduplication under /tmp/homelab/<user>
# ============================================================================

# Ensure SOPS can decrypt inside Make recipes
export SOPS_AGE_KEY_FILE := $(HOME)/.config/sops/age/keys.txt

SOPS             := /usr/local/bin/sops
export SECRETS_FILE  := $(REPO_ROOT)/secrets.enc.yaml

# ----------------------------------------------------------------------------
# 0. RAM-only workspace (per-user)
# ----------------------------------------------------------------------------

HOMELAB_TMP_BASE    := /tmp/homelab
export HOMELAB_TMP_USER := $(HOMELAB_TMP_BASE)/$(shell id -un)

export SECRETS_OBJ_DIR := $(HOMELAB_TMP_USER)/secrets/objects
export SECRETS_REF_DIR := $(HOMELAB_TMP_USER)/secrets/refs
export SECRETS_TMP_DIR := $(HOMELAB_TMP_USER)/secrets/tmp

# Create RAM‑only secrets workspace under /tmp and lock it down to 0700 (prevent cross‑user reads)
$(shell mkdir -p $(SECRETS_OBJ_DIR) $(SECRETS_REF_DIR) $(SECRETS_TMP_DIR) && chmod -R 700 $(HOMELAB_TMP_USER))
$(shell chown -R $(shell id -un):$(shell id -gn) $(HOMELAB_TMP_USER) 2>/dev/null || true)

export SECRETS_LOCK     := $(HOMELAB_TMP_USER)/secrets/lock
export SECRETS_LOCK_PID := $(SECRETS_LOCK)/pid
export SECRETS_LOCK_TS  := $(SECRETS_LOCK)/ts

# Lock expires after N seconds
SECRETS_LOCK_MAX_AGE := 30

# Call as: $(call WITH_SECRETS, <shell commands>)
define WITH_SECRETS
	export $$(/usr/local/bin/sops -d $(REPO_ROOT)/secrets.enc.yaml \
		| awk -F': ' '/: / {gsub(/"/, "", $$2); print $$1 "=" $$2}'); \
	$(1)
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

.PHONY: check-secrets-src
check-secrets-src: sops-init
	@if [ ! -f "$(SECRETS_FILE)" ]; then \
		echo "❌ Error: $(SECRETS_FILE) not found!"; \
		echo "👉 Required one-time activity:"; \
		echo "   SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops $(SECRETS_FILE)"; \
		exit 1; \
	fi

# ----------------------------------------------------------------------------
# Lockfile mechanism with stale lock detection
# ----------------------------------------------------------------------------

define acquire_secrets_lock
	@now=$$(date +%s); \
	if [ -d "$(SECRETS_LOCK)" ]; then \
		if [ -f "$(SECRETS_LOCK_TS)" ]; then \
			ts=$$(cat "$(SECRETS_LOCK_TS)" 2>/dev/null || echo 0); \
			age=$$((now - ts)); \
			if [ $$age -gt $(SECRETS_LOCK_MAX_AGE) ]; then \
				echo "⚠️ Stale secrets lock detected (age $$age s > $(SECRETS_LOCK_MAX_AGE)s). Breaking it."; \
				rm -rf "$(SECRETS_LOCK)"; \
			fi; \
		else \
			echo "⚠️ Lock directory exists but no timestamp — breaking lock."; \
			rm -rf "$(SECRETS_LOCK)"; \
		fi; \
	fi; \
	while ! mkdir "$(SECRETS_LOCK)" 2>/dev/null; do \
		echo "⏳ Waiting for secrets lock..."; \
		sleep 0.1; \
	done; \
	echo "$$" > "$(SECRETS_LOCK_PID)"; \
	echo "$$now" > "$(SECRETS_LOCK_TS)"; \
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "🔒 Acquired secrets lock (pid $$, ts $$now)"; \
	fi
endef

define release_secrets_lock
	@rm -rf "$(SECRETS_LOCK)" 2>/dev/null || true
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "🔓 Released secrets lock"; \
	fi
endef


$(SECRETS_REF_DIR)/secrets.yaml: check-secrets-src
	$(call acquire_secrets_lock)
	@trap 'rm -rf "$(SECRETS_LOCK)" 2>/dev/null || true' EXIT; \
	tmpfile=$$(mktemp "$(SECRETS_TMP_DIR)/secrets.XXXXXX"); \
	$(SOPS) -d "$(SECRETS_FILE)" > "$$tmpfile"; \
	sha=$$(sha256sum "$$tmpfile" | awk '{print $$1}'); \
	obj="$(SECRETS_OBJ_DIR)/$${sha}"; \
	if [ ! -f "$$obj" ]; then cp "$$tmpfile" "$$obj"; fi; \
	printf "%s" "$$obj" > "$(SECRETS_REF_DIR)/secrets.yaml"; \
	rm -f "$$tmpfile"; \
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "🔐 Secrets stored as object $$sha (RAM-only)"; \
	fi
	$(call release_secrets_lock)

# ----------------------------------------------------------------------------
# 6. ddns-conf-generate — ephemeral RAM-only file
# ----------------------------------------------------------------------------

.PHONY: ddns-conf-generate
ddns-conf-generate: $(SECRETS_REF_DIR)/secrets.yaml
	@mkdir -p $(dir $(TMP_DDNS_CONF))
	@$(WITH_SECRETS) \
		umask 077; \
		printf "%s\n%s\n%s\n" \
			"DNS_TOPDOMAIN_NAME='$$ddns_topdomain'" \
			"DDNSUSERNAME='$$ddns_username'" \
			"DDNSPASSWORD='$$ddns_password'" \
			> "$(TMP_DDNS_CONF)"
	@echo "🧩 Generated $(TMP_DDNS_CONF) (RAM only)"

# ----------------------------------------------------------------------------
# 7. Garbage Collection for deduplicated secret objects (POSIX-safe)
# ----------------------------------------------------------------------------

.PHONY: secrets-gc
secrets-gc:
	$(call acquire_secrets_lock)
	@echo "🧹 Running secrets GC under $(HOMELAB_TMP_USER)/secrets"
	@objdir="$(SECRETS_OBJ_DIR)"; \
	refdir="$(SECRETS_REF_DIR)"; \
	\
	reachable_tmp=$$(mktemp); \
	for r in "$$refdir"/*; do \
		[ -f "$$r" ] || continue; \
		cat "$$r"; \
	done | sort -u > $$reachable_tmp; \
	\
	all_tmp=$$(mktemp); \
	find "$$objdir" -maxdepth 1 -type f 2>/dev/null | sort -u > $$all_tmp; \
	\
	unref_tmp=$$(mktemp); \
	comm -23 $$all_tmp $$reachable_tmp > $$unref_tmp; \
	\
	if [ ! -s "$$unref_tmp" ]; then \
		echo "🟢 No unreferenced objects to delete"; \
	else \
		echo "🗑️  Removing unreferenced objects:"; \
		cat $$unref_tmp; \
		xargs rm -f < $$unref_tmp; \
		echo "✅ GC complete"; \
	fi; \
	rm -f $$reachable_tmp $$all_tmp $$unref_tmp; \
	$(call release_secrets_lock)

.PHONY: secrets-status
secrets-status:
	@echo "🔎 Secrets subsystem status"
	@echo "  USER: $(shell id -un)"
	@echo "  BASE: $(HOMELAB_TMP_USER)/secrets"
	@echo ""
	@echo "📁 Directories:"
	@echo "  OBJ:  $(SECRETS_OBJ_DIR)"
	@echo "  REF:  $(SECRETS_REF_DIR)"
	@echo "  LOCK: $(SECRETS_LOCK)"
	@echo ""
	@echo "🔐 Current secrets object:"
	@if [ -f "$(SECRETS_REF_DIR)/secrets.yaml" ]; then \
		obj=$$(cat "$(SECRETS_REF_DIR)/secrets.yaml"); \
		echo "  REF → $$obj"; \
		if [ -f "$$obj" ]; then \
			echo "  SHA → $$(basename $$obj)"; \
		else \
			echo "  ⚠️ Object missing"; \
		fi; \
	else \
		echo "  ⚠️ No secrets loaded"; \
	fi
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
secrets-dump: $(SECRETS_REF_DIR)/secrets.yaml
	@obj=$$(cat "$(SECRETS_REF_DIR)/secrets.yaml"); \
	if [ ! -f "$$obj" ]; then \
		echo "❌ Object $$obj missing"; \
		exit 1; \
	fi; \
	echo "🔐 Dumping decrypted secrets (RAM-only):"; \
	cat "$$obj"

.PHONY: secrets-verify
secrets-verify:
	@echo "🔎 Verifying secrets integrity"
	@if [ ! -f "$(SECRETS_REF_DIR)/secrets.yaml" ]; then \
		echo "❌ No secrets ref found"; exit 1; \
	fi
	@obj=$$(cat "$(SECRETS_REF_DIR)/secrets.yaml"); \
	if [ ! -f "$$obj" ]; then \
		echo "❌ Object file missing: $$obj"; exit 1; \
	fi; \
	sha_file=$$(basename "$$obj"); \
	sha_calc=$$(sha256sum "$$obj" | awk '{print $$1}'); \
	if [ "$$sha_file" != "$$sha_calc" ]; then \
		echo "❌ SHA mismatch!"; \
		echo "   filename: $$sha_file"; \
		echo "   actual:   $$sha_calc"; \
		exit 1; \
	fi; \
	echo "🟢 Secrets object verified (SHA $$sha_file)"

.PHONY: secrets-edit
secrets-edit:
	$(call acquire_secrets_lock)
	@echo "📝 Editing encrypted secrets with SOPS ($(SECRETS_FILE))"
	@TMPDIR="$(SECRETS_TMP_DIR)" $(SOPS) "$(SECRETS_FILE)"
	$(call release_secrets_lock)

secrets-ready:
	@$(WITH_SECRETS) \
		{ [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && echo "Secrets OK (router_addr=$$router_addr)"; } || true

.PHONY: check-age-key
check-age-key: ensure-authorized-admin
	@if [ ! -f /etc/sops/keys/age.key ]; then \
		echo "❌ AGE key missing at /etc/sops/keys/age.key"; exit 1; \
	fi
	@if [ "$$(stat -c %a /etc/sops/keys/age.key)" != "600" ]; then \
		echo "❌ Wrong permissions on AGE key (expected 600)"; exit 1; \
	fi
	@if [ "$$(stat -c %U:%G /etc/sops/keys/age.key)" != "root:root" ]; then \
		echo "❌ Wrong ownership on AGE key (expected root:root)"; exit 1; \
	fi

	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "🔍 Testing SOPS decryption as $(OPERATOR_USER)..."; \
	fi
	@if ! sudo -u "$(OPERATOR_USER)" sops -d secrets.enc.yaml >/dev/null 2>&1; then \
		echo "❌ AGE key exists but cannot decrypt secrets.enc.yaml as $(OPERATOR_USER)"; \
		exit 1; \
	fi

	@echo "🔐 AGE key OK — ts=$$(stat -c '%y' /etc/sops/keys/age.key) pub=$$($(run_as_root) age-keygen -y /etc/sops/keys/age.key) user=$(OPERATOR_USER)"
