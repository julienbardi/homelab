# mk/05_bootstrap_wireguard.mk

WG_ENSURE_SERVER_KEYS := $(INSTALL_PATH)/wg-ensure-server-keys.sh

.PHONY: wg-bootstrap

# Installation rule for the helper script
$(WG_ENSURE_SERVER_KEYS): $(REPO_ROOT)scripts/wg-ensure-server-keys.sh | $(BOOTSTRAP_FILES)
	@echo "📍 Installing WireGuard key utility"
	@$(call install_script,$<,$(notdir $@))

wg-bootstrap: ensure-run-as-root $(WG_ENSURE_SERVER_KEYS)
	@echo "🔧 Bootstrapping WireGuard filesystem layout"

	# Base directory structure
	@$(run_as_root) install -d -m 0750 -o root  -g admin $(HOMELAB_ROOT)
	@$(run_as_root) install -d -m 0750 -o root  -g admin $(WG_ROOT)
	@$(run_as_root) install -d -m 0750 -o root  -g admin $(WG_ROOT)/input
	@$(run_as_root) install -d -m 2770 -o root  -g admin $(WG_ROOT)/compiled
	@$(run_as_root) install -d -m 0750 -o root  -g admin $(WG_ROOT)/scripts

	# Key storage (High sensitivity)
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/server-keys
	@$(run_as_root) install -d -m 2770 -o root  -g admin $(WG_ROOT)/compiled/server-pubkeys
	@$(run_as_root) install -d -m 0700 -o root  -g root  $(WG_ROOT)/compiled/client-keys

	# Output buffers
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/out
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/export/clients
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/out/server
	@$(run_as_root) install -d -m 0700 -o julie -g admin $(WG_ROOT)/out/server/peers

	# System config hook
	@$(run_as_root) install -d -m 0750 -o root -g admin /etc/wireguard

	@echo "🔐 Ensuring initial WireGuard server keys"
	@$(run_as_root) env WG_ROOT=$(WG_ROOT) $(WG_ENSURE_SERVER_KEYS)

	@echo "✅ WireGuard filesystem bootstrapped"