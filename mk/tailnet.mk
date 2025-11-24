# ============================================================
# Tailnet orchestration
# ------------------------------------------------------------
# Registers current host into Headscale namespace and generates
# client config + QR code
# ============================================================

.PHONY: tailnet

# Default device name: system hostname (override with DEVICE_NAME=foo)
DEVICE_NAME ?= $(shell hostname)

tailnet:
	@echo "Registering device $(DEVICE_NAME) into tailnet..."
	sudo ${HOME}/src/homelab/scripts/helpers/tailnet.sh $(DEVICE_NAME)

.PHONY: tailnet-menu-deploy

tailnet-menu-deploy:
    @echo "Deploying tailnet-menu.sh to /usr/local/bin..."
    @$(call run_as_root,cp scripts/helpers/tailnet-menu.sh /usr/local/bin/tailnet-menu)
    @$(call run_as_root,chown root:root /usr/local/bin/tailnet-menu)
    @$(call run_as_root,chmod 755 /usr/local/bin/tailnet-menu)
    @echo "Done. Run 'tailnet-menu' from anywhere."
