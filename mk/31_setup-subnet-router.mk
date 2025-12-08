# ============================================================
# mk/31_setup-subnet-router.mk — Subnet router orchestration
# ============================================================
# CONTRACT:
# - Uses run_as_root := ./bin/run-as-root
# - All recipes call $(run_as_root) with argv tokens.
# - Operators (> | && ||) must be escaped when invoked from Make.
# ============================================================



# --------------------------------------------------------------------
# Install router + firewall systemd units and scripts from repo
# --------------------------------------------------------------------
# Assumes:
#   HOMELAB_DIR is set above and ROUTER_REPO_SYSTEMD := config/systemd
#   run_as_root is provided by mk/01_common.mk
# --------------------------------------------------------------------

ROUTER_SYSTEMD_DIR := /etc/systemd/system
ROUTER_REPO_SYSTEMD := $(HOMELAB_DIR)/config/systemd
ROUTER_REPO_SCRIPTS := $(HOMELAB_DIR)/scripts

# Services that must start after firewall/router units
WG_UNITS := $(foreach i,0 1 2 3 4 5 6 7, wg-quick@wg$(i).service)
FW_DEP_SERVICES := caddy.service tailscaled.service unbound.service headscale.service $(WG_UNITS)

.PHONY: install-router-systemd enable-router-systemd uninstall-router-systemd

install-router-systemd: ## Install router/firewall scripts and systemd units from repo (idempotent)
	@echo "[make] Installing router/firewall scripts and units from $(ROUTER_REPO_SYSTEMD)..."
	@if [ ! -d "$(ROUTER_REPO_SYSTEMD)" ]; then \
		echo "[make] ERROR: $(ROUTER_REPO_SYSTEMD) not found"; exit 1; \
	fi
	@$(run_as_root) mkdir -p $(ROUTER_SYSTEMD_DIR)
	@$(run_as_root) mkdir -p /usr/local/bin

	# install scripts only if changed
	@for s in setup-subnet-router.nft.sh firewall-nft.sh; do \
	  src="$(ROUTER_REPO_SCRIPTS)/$$s"; dest="/usr/local/bin/$$s"; \
	  if [ -f "$$src" ]; then \
		if ! cmp -s "$$src" "$$dest" 2>/dev/null; then \
		  echo "[make] Installing $$src -> $$dest"; \
		  $(run_as_root) install -o root -g root -m 0755 "$$src" "$$dest"; \
		else \
		  echo "[make] Unchanged: $$dest"; \
		fi; \
	  else \
		echo "[make] WARNING: $$src not found in repo"; \
	  fi; \
	done

	# install unit files only if changed
	@for u in setup-subnet-router.service firewall-nft.service; do \
	  src="$(ROUTER_REPO_SYSTEMD)/$$u"; dest="$(ROUTER_SYSTEMD_DIR)/$$u"; \
	  if [ -f "$$src" ]; then \
		if ! cmp -s "$$src" "$$dest" 2>/dev/null; then \
		  echo "[make] Installing $$src -> $$dest"; \
		  $(run_as_root) install -o root -g root -m 0644 "$$src" "$$dest"; \
		else \
		  echo "[make] Unchanged: $$dest"; \
		fi; \
	  else \
		echo "[make] WARNING: $$src not found in repo"; \
	  fi; \
	done

	@$(run_as_root) systemctl daemon-reload
	@echo "[make] Installed router scripts and units."

enable-router-systemd: install-router-systemd
	@echo "[make] Enabling and starting firewall/router units first..."
	@$(run_as_root) systemctl enable --now setup-subnet-router.service || true
	@$(run_as_root) systemctl enable --now firewall-nft.service || true
	@$(run_as_root) systemctl start setup-subnet-router.service || true
	@$(run_as_root) systemctl start firewall-nft.service || true
	@echo "[make] Waiting briefly for firewall units to settle..."
	@sleep 2
	@echo "[make] Enabling/restarting dependent services (unmasking wg units if masked)..."
	# enable/restart other services if present
	@for svc in caddy.service tailscaled.service unbound.service headscale.service; do \
	  if $(run_as_root) systemctl list-unit-files --type=service | grep -q "^$$svc"; then \
		echo "[make] Enabling/restarting $$svc"; \
		$(run_as_root) systemctl enable $$svc || true; \
		$(run_as_root) systemctl restart $$svc || true; \
	  else \
		echo "[make] Skipping missing unit $$svc"; \
	  fi; \
	done
	# handle wg-quick@wg0..wg7 units: unmask if masked, then enable/restart if present
	@for i in 0 1 2 3 4 5 6 7; do \
	  u="wg-quick@wg$$i.service"; \
	  if $(run_as_root) systemctl list-unit-files --type=service | grep -q "^$$u"; then \
		if $(run_as_root) systemctl list-unit-files --type=service | grep -q "^$$u.*masked"; then \
		  echo "[make] Unmasking $$u"; \
		  $(run_as_root) systemctl unmask $$u || true; \
		fi; \
		echo "[make] Enabling/restarting $$u"; \
		$(run_as_root) systemctl enable $$u || true; \
		$(run_as_root) systemctl restart $$u || true; \
	  else \
		echo "[make] $$u not present, skipping"; \
	  fi; \
	done
	@echo "[make] Router units and dependents enabled."

uninstall-router-systemd:
	@echo "[make] Stopping and removing router units and scripts..."
	@$(run_as_root) systemctl stop --now setup-subnet-router.service firewall-nft.service || true
	@$(run_as_root) systemctl disable setup-subnet-router.service firewall-nft.service || true
	@$(run_as_root) rm -f $(ROUTER_SYSTEMD_DIR)/setup-subnet-router.service $(ROUTER_SYSTEMD_DIR)/firewall-nft.service || true
	@$(run_as_root) rm -f /usr/local/bin/setup-subnet-router.nft.sh /usr/local/bin/firewall-nft.sh || true
	@$(run_as_root) systemctl daemon-reload
	@echo "[make] Uninstalled router units and scripts."

.PHONY: bootstrap-router
bootstrap-router: ## Install repo units/scripts, then enable/start router+firewall
	@echo "[make] bootstrap-router: installing repo units/scripts"
	@$(MAKE) install-router-systemd || true
	@echo "[make] bootstrap-router: enabling and starting router units"
	@$(MAKE) enable-router-systemd || true
	@echo "[make] bootstrap-router: done"


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
