# mk/wireguard.mk
# ------------------------------------------------------------
# WireGuard control plane
# ------------------------------------------------------------
#
# Purpose:
#   - Execute WireGuard control-plane compilers on the router
#   - Validate and optionally dump derived state
#
# Contract:
#   - Scripts execute on the router, never locally
#   - No implicit execution
#   - No runtime convergence here
# ------------------------------------------------------------

WG_DIR := $(ROUTER_SCRIPTS)/wireguard
HOST_AWK := /usr/bin/awk
HOST_SHA256SUM := /usr/bin/sha256sum

# yq is a build-host tool; define it here (tools.mk is included later)
YQ := $(TOOLS_DIR)/yq/yq

.PHONY: wg-domain-build
wg-domain-build: $(YQ) domain.tsv
	@echo "🛠️ built domain.tsv"

domain.tsv: domain.yaml
	@set -eu; \
	$(YQ) -r '.interfaces | to_entries[] | .key as $$iface | .value as $$i | ["global", $$iface, ($$i.lan_subnets != null), ($$i.internet // false), $$i.server, ($$i.vpn_subnet.ipv4 // ""), ($$i.vpn_subnet.ipv6 // "")] | @tsv' domain.yaml \
	| sed '1i base\tiface\tlan\twan\tserver\tvpn4_cidr\tvpn6_cidr' \
	> "$@"; \
	[ "$$(wc -l <"$@")" -gt 1 ] || { echo "❌ domain.tsv empty"; exit 1; }

.PHONY: wg-deploy
wg-deploy: domain.tsv
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) 'mkdir -p $(ROUTER_SCRIPTS)'

	@echo "🚀 deploying domain.tsv"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		"mkdir -p '$(WG_DIR)' && cat > '$(WG_DIR)/domain.tsv'" < domain.tsv

	@set -eu; \
	for f in wg-compile-domain.sh wg-compile-alloc.sh wg-compile-keys.sh; do \
		src='$(SRC_SCRIPTS)/'$$f; \
		dst='$(ROUTER_SCRIPTS)/'$$f; \
		lh="$$($(HOST_SHA256SUM) "$$src" | $(HOST_AWK) '{print $$1}')"; \
		rh="$$(ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
			"busybox sha256sum '$$dst' 2>/dev/null" | $(HOST_AWK) '{print $$1}' || true)"; \
		if [ -n "$$rh" ] && [ "$$lh" = "$$rh" ]; then \
			echo "✅ $$f unchanged"; \
		else \
			echo "🚀 deploying $$f"; \
			ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
				"cat > '$$dst' && chmod +x '$$dst'" < "$$src"; \
		fi; \
	done

.PHONY: wg-preflight
wg-preflight:
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		die(){ echo "wg-preflight: ERROR: $$*" >&2; exit 1; }; \
		busybox sha256sum </dev/null >/dev/null 2>&1 || die "busybox sha256sum not available"; \
		busybox awk "BEGIN { exit 0 }" </dev/null || die "busybox awk not available"; \
		[ -d "$(ROUTER_SCRIPTS)" ] || die "missing directory $(ROUTER_SCRIPTS)"; \
		[ -d "$(WG_DIR)" ] || die "missing directory $(WG_DIR)"; \
		[ -f "$(WG_DIR)/domain.tsv" ] || die "missing domain.tsv"; \
		[ -x "$(ROUTER_SCRIPTS)/wg-compile-domain.sh" ] || die "wg-compile-domain.sh missing or not executable"; \
		[ -x "$(ROUTER_SCRIPTS)/wg-compile-alloc.sh" ] || die "wg-compile-alloc.sh missing or not executable"; \
		[ -x "$(ROUTER_SCRIPTS)/wg-compile-keys.sh" ] || die "wg-compile-keys.sh missing or not executable"; \
		echo "✓ wg-preflight OK"; \
	'

.PHONY: wg-check
wg-check: wg-deploy wg-preflight
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'cd "$(WG_DIR)" && WG_DUMP=1 "$(ROUTER_SCRIPTS)/wg-compile-domain.sh"'
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'cd "$(WG_DIR)" && "$(ROUTER_SCRIPTS)/wg-compile-alloc.sh"'
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'cd "$(WG_DIR)" && "$(ROUTER_SCRIPTS)/wg-compile-keys.sh"'
	@echo "✅ WireGuard control-plane check passed"

.PHONY: wg-dump
wg-dump: wg-domain-build wg-deploy wg-preflight
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'cd "$(WG_DIR)" && WG_DUMP=1 "$(ROUTER_SCRIPTS)/wg-compile-domain.sh"'
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'cd "$(WG_DIR)" && WG_DUMP=1 "$(ROUTER_SCRIPTS)/wg-compile-alloc.sh"'
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'cd "$(WG_DIR)" && WG_DUMP=1 "$(ROUTER_SCRIPTS)/wg-compile-keys.sh"'
	@echo "📦 WireGuard control-plane dumps generated"

