# mk/05_bootstrap_wireguard.mk
# BOOTSTRAP (run once on a fresh system):
#  make prereqs
#  make wg-bootstrap

WG_ENSURE_SERVER_KEYS := $(INSTALL_PATH)/wg-ensure-server-keys.sh

.PHONY: wg-bootstrap

wg-bootstrap: ensure-run-as-root $(WG_ENSURE_SERVER_KEYS)
	@echo "🔧 Bootstrapping WireGuard filesystem layout"

	@$(run_as_root) install -d -m 0750 -o root  -g admin $(HOMELAB_ROOT)
	@$(run_as_root) install -d -m 0750 -o root  -g admin $(WG_ROOT)
	@$(run_as_root) install -d -m 0750 -o root  -g admin $(WG_ROOT)/input
	@$(run_as_root) install -d -m 2770 -o root  -g admin $(WG_ROOT)/compiled
	@$(run_as_root) install -d -m 0750 -o root  -g admin $(WG_ROOT)/scripts
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/server-keys
	@$(run_as_root) install -d -m 2770 -o root  -g admin $(WG_ROOT)/compiled/server-pubkeys
	@$(run_as_root) install -d -m 0700 -o root  -g root  $(WG_ROOT)/compiled/client-keys
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/out
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/export/clients
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/out/server
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/out/server/peers

	@$(run_as_root) install -d -m 0750 -o root -g admin /etc/wireguard

	@echo "🔐 Ensuring initial WireGuard server keys"
	@$(run_as_root) env WG_ROOT=$(WG_ROOT) $(WG_ENSURE_SERVER_KEYS)

	@echo "✅ WireGuard filesystem bootstrapped"
