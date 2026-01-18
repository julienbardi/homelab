# mk/80_tailnet.mk
# Tailnet orchestration
# ------------------------------------------------------------
# Registers current host into Headscale namespace and generates
# client config + QR code
# ============================================================

BIN_DIR ?= /usr/local/bin

TAILNET_BIN      := $(BIN_DIR)/tailnet.sh 
TAILNET_MENU_BIN := $(BIN_DIR)/tailnet-menu.sh

# Default device name: system hostname (override with DEVICE_NAME=foo)
DEVICE_NAME ?= $(shell hostname)

.PHONY: tailnet tailnet-menu-deploy

# -------------------------------------------------
# Public targets
# -------------------------------------------------

tailnet: $(TAILNET_BIN)
	@echo "Registering device $(DEVICE_NAME) into tailnet..."
	@$(run_as_root) $(TAILNET_BIN) $(DEVICE_NAME)

tailnet-menu-deploy: $(TAILNET_MENU_BIN)
	@echo "tailnet-menu installed. Run 'tailnet-menu' from anywhere."
