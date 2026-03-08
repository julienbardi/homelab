# mk/help.mk
# ------------------------------------------------------------
# OPERATOR HELP SURFACE
# ------------------------------------------------------------
#
# Purpose:
#   - Provide a truthful, side‑effect‑free overview of available targets
#   - Reflect only targets that actually exist in included modules
#
# Contract:
#   - MUST NOT invoke other targets
#   - MUST NOT perform side effects
# ------------------------------------------------------------

.PHONY: help
help:
	@echo "Homelab router Makefile — available targets:"
	@echo
	@echo "Router access & diagnostics:"
	@echo "  make ssh-check              Verify non-interactive SSH access to router"
	@echo "  make router-health          Read-only router health check"
	@echo "  make router-health-strict   Enforce strict security invariants"
	@echo
	@echo "Router bootstrap & firewall:"
	@echo "  make bootstrap              Install helpers and converge base services"
	@echo "  make firewall               Assert Skynet firewall enforcement"
	@echo "  make firewall-install       Deploy firewall hook script"
	@echo "  make firewall-started       Assert base firewall is running"
	@echo "  make firewall-hardened      Assert full firewall hardening"
	@echo "  make firewall-audit         Dump firewall rules and WireGuard state"
	@echo
	@echo "Certificates (internal CA):"
	@echo "  make certs-create           Create internal CA (idempotent)"
	@echo "  make certs-deploy           Deploy certificates to router"
	@echo "  make certs-ensure           Ensure CA exists and is deployed"
	@echo "  make certs-status           Show deployed certificate status"
	@echo "  make certs-expiry           Show CA expiry date"
	@echo "  make certs-rotate-dangerous Rotate CA (DESTRUCTIVE, confirmation required)"
	@echo "  make deploy-router          Deploy router certificates"
	@echo "  make validate-router        Validate router certificates"
	@echo "  make validate-caddy         Validate Caddy certificates"
	@echo
	@echo "Caddy (router edge):"
	@echo "  make caddy-install          Install Caddy binary on router"
	@echo "  make caddy-config           Push and validate Caddy configuration"
	@echo "  make deploy-caddy           Full Caddy deployment"
	@echo "  make caddy                  Alias for deploy-caddy"
	@echo "  make caddy-status           Show Caddy process status"
	@echo "  make caddy-start            Start Caddy"
	@echo "  make caddy-stop             Stop Caddy"
	@echo
	@echo "WireGuard (control plane):"
	@echo "  make wg-deploy              Deploy WireGuard compiler scripts to router"
	@echo "  make wg-check               Run WireGuard compilers on router"
	@echo "  make wg-dump                Run WireGuard compilers with WG_DUMP=1"
	@echo
	@echo "Local developer tools:"
	@echo "  make lint                   Lint Makefiles with checkmake"
	@echo "  make tools                  Install local tooling"
	@echo "  make spellcheck             Interactive spellcheck of markdown files"
	@echo "  make spellcheck-comments    Spellcheck Makefile comments"
	@echo "  make distclean              Remove local tools and staged scripts"
