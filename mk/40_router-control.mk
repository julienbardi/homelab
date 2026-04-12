# mk/40_router-control.mk
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
#   - Assemble router control-plane submodules
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
		|| echo "❌ CAP_FILE_DEPLOY:        unavailable → file deployment not possible"

	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'command -v sha256sum >/dev/null 2>&1 || echo test | busybox sha256sum >/dev/null 2>&1' \
		&& echo "✅ CAP_CONTENT_ADDRESSING: enabled (sha256sum or busybox sha256sum)" \
		|| echo "⚠️  CAP_CONTENT_ADDRESSING: sha256sum unavailable → content-addressed deployment degraded"

	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '[ -x /jffs/scripts/firewall-start ]' >/dev/null 2>&1 \
		&& echo "✅ CAP_FIREWALL:           enabled (firewall-start hook)" \
		|| echo "⚠️  CAP_FIREWALL:           degraded → no firewall-start hook"

	@echo
	@echo "ℹ️  Informational only — no enforcement performed"

# ------------------------------------------------------------
# ROUTER CONTROL PLANE (namespaced, already include in mk/graph.mk)
# ------------------------------------------------------------

include $(REPO_ROOT)mk/router/05_ssh.mk
include $(REPO_ROOT)mk/router/10_bootstrap.mk
#include $(REPO_ROOT)mk/router/20_firewall.mk
#include $(REPO_ROOT)mk/router/20_wireguard.mk
#include $(REPO_ROOT)mk/router/40_router-wireguard.mk
include $(REPO_ROOT)mk/router/90_health.mk

# ------------------------------------------------------------
# Router readiness
# ------------------------------------------------------------

.PHONY: router-ready
router-ready: router-firewall-hardened router-dnsmasq-cache
	@echo "🛡️ Router base services converged"

.PHONY: router-prepare
router-prepare: router-ready router-require-run-as-root router-certs-prepare

# ------------------------------------------------------------
# ROUTER FULL CONVERGENCE
# ------------------------------------------------------------

.PHONY: router-converge
router-converge: \
	router-ssh-check \
	router-bootstrap \
	router-firewall-hardened \
	router-certs-deploy \
	router-caddy \
	router-wg-check \
	router-health \
	router-health-strict
	@echo "🚀 Router fully converged"

.PHONY: router-verify
router-verify: \
	router-ssh-check \
	router-firewall-hardened \
	router-wg-health-strict \
	router-wg-audit \
	router-health-strict
	@echo "✅ Router verification passed"
