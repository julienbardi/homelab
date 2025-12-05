# ============================================================
# mk/31_setup-subnet-router.mk — Subnet router orchestration
# ============================================================
# CONTRACT:
# - Uses run_as_root := ./bin/run-as-root
# - All recipes call $(run_as_root) with argv tokens.
# - Operators (> | && ||) must be escaped when invoked from Make.
# ============================================================

.PHONY: install-wireguard-tools setup-subnet-router router-deploy router-logs

# --- WireGuard prerequisites ---
install-wireguard-tools:
	@echo "[make] Installing WireGuard kernel module + tools"
	@$(run_as_root) apt-get update
	@$(run_as_root) apt-get install -y wireguard wireguard-tools netfilter-persistent iptables-persistent ethtool

# --- Subnet router deployment ---
SCRIPT_SRC  := $(HOMELAB_DIR)/scripts/setup/setup-subnet-router.sh
SCRIPT_DST  := /usr/local/bin/setup-subnet-router
UNIT_SRC    := $(HOMELAB_DIR)/config/systemd/subnet-router.service
UNIT_DST    := /etc/systemd/system/subnet-router.service

setup-subnet-router: update install-wireguard-tools | $(SCRIPT_SRC) $(UNIT_SRC)
	@echo "[make] Deploying subnet router script + service..."
	@if [ ! -f "$(SCRIPT_SRC)" ]; then \
		echo "[make] ERROR: $(SCRIPT_SRC) not found"; exit 1; \
	fi
	@if [ ! -f "$(UNIT_SRC)" ]; then \
		echo "[make] ERROR: $(UNIT_SRC) not found"; exit 1; \
	fi
	@COMMIT_HASH=$$(git -C $(HOMELAB_DIR) rev-parse --short HEAD); \
		$(run_as_root) install -m 0755 -o root -g root $(SCRIPT_SRC) $(SCRIPT_DST); \
		$(run_as_root) install -m 0644 -o root -g root $(UNIT_SRC) $(UNIT_DST); \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) systemctl enable --now subnet-router.service; \
		echo "[make] Deployed commit $$COMMIT_HASH to $(SCRIPT_DST) and installed subnet-router.service"

# --- Convenience aliases ---
router-deploy:
	@echo "[make] Copying updated setup-subnet-router.sh and restarting service"
	@$(run_as_root) install -m 0755 -o root -g root $(ROUTER_SCRIPT) $(ROUTER_BIN)
	@$(run_as_root) systemctl restart $(SERVICE)

router-logs:
	@echo "[make] Tailing live logs for $(SERVICE) (Ctrl+C to exit)..."
	@$(run_as_root) journalctl -u $(SERVICE) -f -n 50 | sed -u \
		-e 's/warning:/⚠️ warning:/g' \
		-e 's/error:/❌ error:/g' \
		-e 's/notice:/ℹ️ notice:/g'
