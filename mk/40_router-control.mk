# mk/router.mk
# ------------------------------------------------------------
# ROUTER CONTROL PLANE
# ------------------------------------------------------------
#
# Purpose:
#   Root assembly for the router control plane.
#
# Scope:
#   - Orchestration only
#   - No stateful behavior
#
# Ownership:
#   - All stateful logic lives in submodules included below
#   - This file must not grow beyond coordination primitives
#
# Responsibilities:
#   - Define control-plane root
#   - Provide shared deployment macros
#   - Assemble router submodules
#
# Concurrency:
#   - Targets listed in .NOTPARALLEL MUST NOT run concurrently
#
# Contracts:
#   - MUST NOT invoke $(MAKE)
#   - MUST be correct under 'make -j'
#   - MUST NOT rely on timestamps for remote state
#
# ------------------------------------------------------------

# ------------------------------------------------------------
# Control-plane primitives
#
# deploy_if_changed:
#   - Content-addressed deployment (SHA256)
#   - Atomic remote update via temp file + rename
#   - No timestamp reliance
#
# Requirements:
#   - ssh, scp available on router
#   - SHA-256 hashing via sha256sum(1) OR busybox sha256sum
# ------------------------------------------------------------

# Capability probe:
#   - Detects available local and remote tools
#   - Reports which control-plane features are enabled, degraded, or unavailable
#   - Does NOT enforce policy or fail builds
# NOTE:
#   This probe reports high-level control-plane capabilities.
#   Individual recipes remain responsible for asserting their own tool dependencies.
.PHONY: check-tools
check-tools:
	@echo "🔍 Router capability report"
	@echo

	@command -v ssh >/dev/null 2>&1 \
		&& echo "✅ CAP_REMOTE_EXEC:        enabled (ssh)" \
		|| echo "❌ CAP_REMOTE_EXEC:        unavailable → no remote recipes possible"

	@command -v scp >/dev/null 2>&1 \
		&& echo "✅ CAP_FILE_DEPLOY:        enabled (scp)" \
		|| echo "❌ CAP_FILE_DEPLOY:        unavailable → deploy_if_changed disabled"

	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'command -v sha256sum >/dev/null 2>&1 || echo test | busybox sha256sum >/dev/null 2>&1' \
		&& echo "✅ CAP_CONTENT_ADDRESSING: enabled (sha256sum or busybox sha256sum)" \
		|| echo "⚠️  CAP_CONTENT_ADDRESSING: sha256sum unavailable → deploy_if_changed cannot compare hashes"

	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '[ -x /jffs/scripts/firewall-start ]' >/dev/null 2>&1 \
		&& echo "✅ CAP_FIREWALL:           enabled (firewall-start hook)" \
		|| echo "⚠️  CAP_FIREWALL:           degraded → no firewall-start hook"

	@echo
	@echo "ℹ️  Informational only — no enforcement performed"

# Contract:
#   - deploy_if_changed is safe-by-construction: it verifies required local and remote tools
#     before performing any remote state changes.
define deploy_if_changed
	@set -e; \
	for cmd in ssh scp sed awk; do \
		command -v $$cmd >/dev/null 2>&1 || { \
			echo "❌ Missing required local command: $$cmd" >&2; exit 1; }; \
	done; \
	SRC="$$(echo '$(1)' | sed 's/^ *//;s/ *$$//')"; \
	[ -f "$$SRC" ] || { echo "❌ Missing source: $$SRC" >&2; exit 1; }; \
	DST="$$(echo '$(2)' | sed 's/^ *//;s/ *$$//')"; \
	TMP="$$DST.tmp.$$"; \
	LOCAL_SHA=$$(sha256sum "$$SRC" | awk '{print $$1}'); \
	REMOTE_SHA=$$(ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) "\
		if [ -f '$$DST' ]; then \
			if command -v sha256sum >/dev/null 2>&1; then \
				sha256sum '$$DST' | sed 's/ .*//'; \
			else \
				/bin/busybox sha256sum '$$DST' | sed 's/ .*//'; \
			fi; \
		fi" || true); \
	if [ "$$LOCAL_SHA" != "$$REMOTE_SHA" ]; then \
		echo "🚀 Deploying $$(basename "$$DST")..."; \
		ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
			"/bin/busybox mkdir -p '$$(dirname "$$DST")' && /bin/busybox rm -f '$$TMP'"; \
		scp -q -O -P $(ROUTER_SSH_PORT) "$$SRC" "$(ROUTER_HOST):$$TMP"; \
		UPLOADED_SHA=$$(ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) "\
			if command -v sha256sum >/dev/null 2>&1; then \
				sha256sum '$$TMP' | sed 's/ .*//'; \
			else \
				/bin/busybox sha256sum '$$TMP' | sed 's/ .*//'; \
			fi"); \
		[ "$$LOCAL_SHA" = "$$UPLOADED_SHA" ] || { \
			echo '❌ Uploaded file hash mismatch' >&2; exit 1; }; \
		ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
			"/bin/busybox chmod 0755 '$$TMP' && /bin/busybox mv -f '$$TMP' '$$DST'"; \
		echo "✅ $$(basename "$$DST") updated"; \
	else \
		echo "✨ $$(basename "$$DST") already up-to-date"; \
	fi
endef



include mk/router/ssh.mk
include mk/router/bootstrap.mk
include mk/router/firewall.mk
include mk/router/health.mk

.PHONY: router-ready
router-ready: firewall-hardened dnsmasq-cache
	@echo "🛡️ Router base services converged"

.PHONY: router-prepare
router-prepare: router-ready require-run-as-root certs-prepare
