# mk/05_bootstrap_wireguard.mk
# BOOTSTRAP (run once on a fresh system):
#  make prereqs
#  make wg-bootstrap

.PHONY: wg-bootstrap

wg-bootstrap:
	@echo "[make] Bootstrapping WireGuard filesystem layout"

	@$(run_as_root) install -d -m 0750 -o root  -g admin /volume1/homelab
	@$(run_as_root) install -d -m 0750 -o root  -g admin /volume1/homelab/wireguard
	@$(run_as_root) install -d -m 0750 -o root  -g admin /volume1/homelab/wireguard/input
	@$(run_as_root) install -d -m 2770 -o root  -g admin /volume1/homelab/wireguard/compiled
	@$(run_as_root) install -d -m 0750 -o root  -g admin /volume1/homelab/wireguard/scripts
	@$(run_as_root) install -d -m 0700 -o julie -g admin /volume1/homelab/wireguard/server-keys
	@$(run_as_root) install -d -m 2770 -o root  -g admin /volume1/homelab/wireguard/compiled/server-pubkeys
	@$(run_as_root) install -d -m 0700 -o root  -g root  /volume1/homelab/wireguard/compiled/client-keys
	@$(run_as_root) install -d -m 0700 -o julie -g admin /volume1/homelab/wireguard/out
	@$(run_as_root) install -d -m 0700 -o julie -g admin /volume1/homelab/wireguard/out/clients
	@$(run_as_root) install -d -m 0700 -o julie -g admin /volume1/homelab/wireguard/out/server
	@$(run_as_root) install -d -m 0700 -o julie -g admin /volume1/homelab/wireguard/out/server/peers

	@$(run_as_root) install -d -m 0750 -o root -g admin /etc/wireguard
	@$(run_as_root) install -d -m 0750 -o julie -g admin /volume1/homelab/wireguard/export/clients

	@echo "[make] Ensuring initial WireGuard server keys"
	@$(run_as_root) env WG_ROOT=$(WG_ROOT) $(CURDIR)/scripts/wg-ensure-server-keys.sh

	@echo "✅ [make] WireGuard filesystem bootstrapped"
