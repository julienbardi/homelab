# mk/router/bootstrap.mk
# ------------------------------------------------------------
# ROUTER BOOTSTRAP & BASELINE PROVISIONING
# ------------------------------------------------------------
#
# Responsibilities:
#   - Install privileged helper scripts
#   - Install DDNS integration
#   - Provision IPv6 ULA support
#   - Perform initial router bootstrap
#
# Non-responsibilities:
#   - Firewall rule enforcement
#   - Service lifecycle management
#   - Health or security assertions
#
# Contracts:
#   - Owns all bootstrap-time router artifacts
#   - State-mutating targets MUST be serialized
#   - MUST be correct under 'make -j'
# ------------------------------------------------------------

.NOTPARALLEL: \
	install-run-as-root \
	install-ddns \
	install-ipv6-ula

.PHONY: install-run-as-root
install-run-as-root: | ssh-check
	$(call deploy_if_changed,$(SRC_SCRIPTS)/run-as-root.sh,$(RUN_AS_ROOT))

.PHONY: install-ddns
install-ddns: | ssh-check
	$(call deploy_if_changed,$(SRC_DDNS)/ddns-start,$(ROUTER_SCRIPTS)/ddns-start)

.PHONY: install-ipv6-ula
install-ipv6-ula: | ssh-check
	$(call deploy_if_changed,$(SRC_SCRIPTS)/provision-ipv6-ula.sh,/jffs/scripts/provision-ipv6-ula.sh)

.PHONY: ensure-ipv6-ula
ensure-ipv6-ula: install-ipv6-ula
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '/jffs/scripts/provision-ipv6-ula.sh'

.PHONY: bootstrap
bootstrap: install-run-as-root install-ddns dnsmasq-cache firewall-install
	@echo "✅ Bootstrap complete"
