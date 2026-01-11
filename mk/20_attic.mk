# ------------------------------------------------------------
# mk/20_attic.mk — Attic CAS Integration
# Transparent LAN cache for downloads.
# Falls back to direct download when Attic is unavailable.
# ------------------------------------------------------------
ATTIC_ROOT ?= /volume1/homelab/attic
ATTIC_INDEX_DIR := $(ATTIC_ROOT)/index
ATTIC_DB := $(ATTIC_INDEX_DIR)/index.sqlite
# Readiness marker under ATTIC_ROOT reflects a running, validated service
ATTIC_READY ?= $(ATTIC_ROOT)/.ready
ATTIC_SERVER ?= http://nas:8082
ATTIC_CLIENT_BIN ?= /usr/local/bin/attic
ATTIC_SERVER_BIN ?= /usr/local/bin/atticd

# Attic server revision
# Pinned to upstream main because Attic publishes no releases or tags.
# Commit chosen after manual review of upstream history.
ATTIC_REF := 12cbeca
export ATTIC_REF

# Source-controlled Attic configuration
SRC_ATTIC_CONFIG  := $(HOMELAB_DIR)/config/attic/config.toml
SRC_ATTIC_SERVICE := $(HOMELAB_DIR)/config/systemd/attic.service

# These must be exported so they exist in the environment *before* privilege
# escalation. bin/run-as-root uses `sudo --preserve-env=…`, which only forwards
# variables already present in the caller’s environment; Make variables alone
# are not visible to sudo or the root process.
export SRC_ATTIC_CONFIG
export SRC_ATTIC_SERVICE

# Detect whether Attic is available
ifeq ($(wildcard $(ATTIC_READY)),)
	ATTIC_AVAILABLE := 0
else
	ATTIC_AVAILABLE := 1
endif

# ------------------------------------------------------------
# Helper: compute SHA256 of a string (URL)
# ------------------------------------------------------------
sha256 = $(shell printf "%s" "$(1)" | sha256sum | awk '{print $$1}')

# ------------------------------------------------------------
# attic_fetch — CAS-aware downloader
# ------------------------------------------------------------
define attic_fetch
	echo "→ Fetching: $(1)"
	HASH=$$(printf "%s" "$(1)" | sha256sum | awk '{print $$1}'); \
	if [ "$(ATTIC_AVAILABLE)" = "1" ] && [ -x "$(ATTIC_CLIENT_BIN)" ]; then \
		echo "   • Attic available → checking cache"; \
		if $(ATTIC_CLIENT_BIN) exists $(ATTIC_SERVER) $$HASH >/dev/null 2>&1; then \
			echo "   • Cache hit → pulling from Attic"; \
			$(ATTIC_CLIENT_BIN) pull $(ATTIC_SERVER) $$HASH > "$(2)"; \
		else \
			echo "   • Cache miss → downloading"; \
			curl -L "$(1)" -o "$(2)"; \
			echo "   • Uploading to Attic"; \
			$(run_as_root) $(ATTIC_CLIENT_BIN) push $(ATTIC_SERVER) $$HASH "$(2)"; \
		fi; \
	else \
		echo "   • Attic unavailable → direct download"; \
		curl -L "$(1)" -o "$(2)"; \
	fi
endef

# ------------------------------------------------------------
# Operator targets
# ------------------------------------------------------------

.PHONY: attic-status
attic-status: ensure-run-as-root
	@echo "→ Attic service status"
	@$(run_as_root) systemctl status attic --no-pager || true

.PHONY: attic-restart
attic-restart: ensure-run-as-root
	@echo "→ Restarting Attic service"
	@$(run_as_root) systemctl restart attic

.PHONY: attic-gc
attic-gc: ensure-run-as-root
	@echo "→ Running Attic garbage collection"
	@$(run_as_root) $(ATTIC_CLIENT_BIN) gc $(ATTIC_SERVER)

.PHONY: attic-info
attic-info: ensure-run-as-root
	@echo "→ Attic server info"
	@$(run_as_root) $(ATTIC_CLIENT_BIN) info $(ATTIC_SERVER)

# ------------------------------------------------------------
# Attic CAS end-to-end test
# ------------------------------------------------------------

.PHONY: attic-test
attic-test:
	@echo "→ Testing Attic CAS end-to-end"
	@TMP1=$$(mktemp); \
	 TMP2=$$(mktemp); \
	 URL="https://example.com"; \
	 HASH=$$(printf "%s" "$$URL" | sha256sum | awk '{print $$1}'); \
	 echo "   Downloading test file"; \
	 curl -sL "$$URL" -o "$$TMP1"; \
	 echo "   Pushing to Attic"; \
	 $(ATTIC_CLIENT_BIN) push $(ATTIC_SERVER) $$HASH "$$TMP1"; \
	 echo "   Pulling back"; \
	 $(ATTIC_CLIENT_BIN) pull $(ATTIC_SERVER) $$HASH > "$$TMP2"; \
	 echo "   Verifying"; \
	 diff "$$TMP1" "$$TMP2" && echo "   ✔ Attic CAS test passed" || echo "   ✘ Attic CAS test failed"

# ------------------------------------------------------------
# attic_store_local — CAS push for local files
# ------------------------------------------------------------
define attic_store_local
	echo "→ Storing local file in Attic: $(1)"
	HASH=$$(sha256sum "$(1)" | awk '{print $$1}'); \
	if [ "$(ATTIC_AVAILABLE)" = "1" ] && [ -x "$(ATTIC_CLIENT_BIN)" ]; then \
		echo "   • Attic available → pushing"; \
		$(run_as_root) $(ATTIC_CLIENT_BIN) push $(ATTIC_SERVER) $$HASH "$(1)"; \
	else \
		echo "   • Attic unavailable → skipping"; \
	fi
endef

.PHONY: attic-db-init
attic-db-init: ensure-run-as-root
	@echo "[make] → Ensuring Attic SQLite database exists"
	@$(run_as_root) install -d -m 0755 "$(ATTIC_INDEX_DIR)"
	@$(run_as_root) test -f "$(ATTIC_DB)" || \
		$(run_as_root) install -m 0644 /dev/null "$(ATTIC_DB)"
	@$(run_as_root) /usr/bin/sqlite3 "$(ATTIC_DB)" 'PRAGMA journal_mode=WAL;' >/dev/null

# ------------------------------------------------------------
# Install Attic server (system-wide)
# ------------------------------------------------------------

.PHONY: attic-install
attic-install: rust-system attic-db-init | ensure-run-as-root
	@echo "[make] → Installing Attic (client + server)"
	@NIX_MAIN_NO_PKG_CONFIG=1 \
		PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/nix/pkgconfig" \
		SRC_ATTIC_CONFIG="$(SRC_ATTIC_CONFIG)" \
		SRC_ATTIC_SERVICE="$(SRC_ATTIC_SERVICE)" \
		$(run_as_root) "$(HOMELAB_DIR)/scripts/bootstrap-attic.sh" || true

	@echo "[make] → Validating Attic configuration"
	@$(run_as_root) sh -c 'timeout 2s $(ATTIC_SERVER_BIN) --config "$(ATTIC_ROOT)/config.toml" >/dev/null || [ $$? -eq 124 ]'
	@$(run_as_root) systemctl enable --now attic || { \
		echo "[make] ❌ Attic service failed to start"; \
		echo "[make] → systemctl status attic"; \
		$(run_as_root) systemctl status attic --no-pager; \
		exit 1; \
	}

# ------------------------------------------------------------
# Readiness marker
# ------------------------------------------------------------

$(ATTIC_READY): attic-install
	@echo "[make] → Verifying Attic service"
	@$(run_as_root) systemctl is-active --quiet attic
	@echo "[make] ✅ Attic ready (marker created)"
	@$(run_as_root) touch $(ATTIC_READY)

# ------------------------------------------------------------
# Canonical operator target
# ------------------------------------------------------------

.PHONY: attic
attic: $(ATTIC_READY)
	@echo "[make] Attic is installed, configured, and ready"

# ------------------------------------------------------------
# Remove Attic completely
# ------------------------------------------------------------

.PHONY: attic-remove
attic-remove: ensure-run-as-root
	@echo "[make] 🗑️ Removing Attic (binary, service, data)"
	@$(run_as_root) rm -f "$(ATTIC_READY)"
	@$(run_as_root) systemctl stop attic >/dev/null 2>&1 || true
	@$(run_as_root) systemctl disable attic >/dev/null 2>&1 || true
	@$(run_as_root) rm -f /etc/systemd/system/attic.service
	@$(run_as_root) systemctl daemon-reload >/dev/null 2>&1 || true
	@$(run_as_root) rm -f "$(ATTIC_CLIENT_BIN)" "$(ATTIC_SERVER_BIN)"
	@$(run_as_root) rm -rf $(ATTIC_ROOT)
	@echo "[make] ✅ Attic removed (service, binary, data, marker)"

.PHONY: attic-update
attic-update: ensure-run-as-root attic-install attic-restart
	@echo "[make] ✅ Attic updated and service restarted"

# ------------------------------------------------------------
# Attic fetch with time-bucketed cache (N seconds)
# ------------------------------------------------------------
# $(1) = URL
# $(2) = destination file
# $(3) = cache window in seconds (e.g. 3600)
define attic_fetch_window
	URL="$(1)"; DEST="$(2)"; WINDOW="$(3)"; \
	SLICE=$$(date -u +%s | awk '{print int($$1 / WINDOW)}'); \
	KEY="$${URL}@$${SLICE}"; \
	HASH=$$(printf "%s" "$$KEY" | sha256sum | awk '{print $$1}'); \
	echo "→ Fetching (cache window=$${WINDOW}s): $$URL"; \
	if [ "$(ATTIC_AVAILABLE)" = "1" ] && [ -x "$(ATTIC_CLIENT_BIN)" ] && \
	   $(ATTIC_CLIENT_BIN) exists $(ATTIC_SERVER) $$HASH >/dev/null 2>&1; then \
		echo "   • Cache hit (slice $$SLICE)"; \
		$(ATTIC_CLIENT_BIN) pull $(ATTIC_SERVER) $$HASH > "$$DEST"; \
	else \
		echo "   • Cache miss → downloading"; \
		curl -fsSL "$$URL" -o "$$DEST"; \
		if [ "$(ATTIC_AVAILABLE)" = "1" ] && [ -x "$(ATTIC_CLIENT_BIN)" ]; then \
			echo "   • Uploading to Attic"; \
			$(run_as_root) $(ATTIC_CLIENT_BIN) push $(ATTIC_SERVER) $$HASH "$$DEST"; \
		fi; \
	fi
endef

# Attic client installation (Cargo-based, no Nix)
# fails 
# The system library `nix-main` required by crate `attic` was not found.
# The file `nix-main.pc` needs to be installed
#
ATTIC_REPO        := https://github.com/zhaofengli/attic.git
ATTIC_SRC         := /usr/local/src/attic
ATTIC_CLIENT_BIN  := /usr/local/bin/attic

STAMP_ATTIC_CLIENT := $(STAMP_DIR)/attic-client.installed

.PHONY: install-attic-client remove-attic-client

install-attic-client: ensure-run-as-root
	@echo "📦 Installing Attic client (Cargo build)"
	@$(run_as_root) install -d -m 0755 $(STAMP_DIR)
	@if [ -x "$(ATTIC_CLIENT_BIN)" ] && [ -f "$(STAMP_ATTIC_CLIENT)" ]; then \
		echo "[make] Attic client already installed; skipping"; \
		exit 0; \
	fi
	@if [ ! -d "$(ATTIC_SRC)/.git" ]; then \
		echo "[make] Cloning Attic source"; \
		$(run_as_root) mkdir -p "$(dir $(ATTIC_SRC))"; \
		$(run_as_root) git clone "$(ATTIC_REPO)" "$(ATTIC_SRC)"; \
	fi
	@echo "[make] Checking out Attic revision $(ATTIC_REF)"
	@$(run_as_root) git -C "$(ATTIC_SRC)" \
		-c safe.directory="$(ATTIC_SRC)" \
		fetch --tags
	@$(run_as_root) git -C "$(ATTIC_SRC)" \
		-c safe.directory="$(ATTIC_SRC)" \
		-c advice.detachedHead=false \
		checkout "$(ATTIC_REF)"
	@echo "[make] Building Attic client"
	@$(run_as_root) bash -c 'cd "$(ATTIC_SRC)" && cargo build --release -p attic-client'
	@$(run_as_root) install -m 0755 "$(ATTIC_SRC)/target/release/attic" "$(ATTIC_CLIENT_BIN)"
	@echo "version=$(ATTIC_REF) installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee "$(STAMP_ATTIC_CLIENT)" >/dev/null
	@echo "✅ Attic client installed"

remove-attic-client: ensure-run-as-root
	@echo "🗑️ Removing Attic client"
	@$(run_as_root) rm -f "$(ATTIC_CLIENT_BIN)" "$(STAMP_ATTIC_CLIENT)"
	@echo "✅ Attic client removed"
