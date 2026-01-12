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
			$(ATTIC_CLIENT_BIN) push $(ATTIC_SERVER) $$HASH "$(2)"; \
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
attic-gc:
	@echo "→ Running Attic garbage collection"
	@$(ATTIC_CLIENT_BIN) gc $(ATTIC_SERVER)

.PHONY: attic-info
attic-info:
	@echo "→ Attic server info"
	@$(ATTIC_CLIENT_BIN) info $(ATTIC_SERVER)

# ------------------------------------------------------------
# Attic CAS end-to-end test
# ------------------------------------------------------------

.PHONY: attic-test
attic-test:
	@echo "→ Testing Attic binary cache end-to-end"

	@echo "   Ensuring Attic cache exists"
	@$(ATTIC_CLIENT_BIN) cache create homelab >/dev/null 2>&1 || true

	@echo "   Configuring Nix to use Attic cache"
	@$(ATTIC_CLIENT_BIN) use homelab

	@echo "   Building test derivation (initial build)"
	@nix build nixpkgs#hello --no-link

	@echo "   Rebuilding to verify cache hit"
	@nix build nixpkgs#hello --no-link --rebuild

	@echo "   ✔ Attic binary cache test passed"

# ------------------------------------------------------------
# attic_store_local — CAS push for local files
# ------------------------------------------------------------
define attic_store_local
	echo "→ Storing local file in Attic: $(1)"
	HASH=$$(sha256sum "$(1)" | awk '{print $$1}'); \
	if [ "$(ATTIC_AVAILABLE)" = "1" ] && [ -x "$(ATTIC_CLIENT_BIN)" ]; then \
		echo "   • Attic available → pushing"; \
		$(ATTIC_CLIENT_BIN) push $(ATTIC_SERVER) $$HASH "$(1)"; \
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
	@echo "1️⃣ Create a token on the NAS (once)"
	@echo "atticadm make-token --sub homelab-client --validity '3 months' --create-cache homelab --push homelab --pull homelab"
	@echo "2️⃣ Distribute the token securely"
	@echo "3️⃣ Non‑interactive login on the client"
	@echo "attic login homelab http://nas:8082 <token>"

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
			$(ATTIC_CLIENT_BIN) push $(ATTIC_SERVER) $$HASH "$$DEST"; \
		fi; \
	fi
endef

# ------------------------------------------------------------
# Attic client installation (Nix-based)
# ------------------------------------------------------------

ATTIC_CLIENT_WRAPPER := $(HOMELAB_DIR)/bin/attic
ATTIC_CLIENT_PROFILE ?= github:zhaofengli/attic

.PHONY: install-attic-client remove-attic-client attic-client-status

install-attic-client: ensure-run-as-root ensure-nix-command
	@echo "📦 Installing Attic client (Nix-based)"
	@$(HOMELAB_DIR)/scripts/install-attic-client-nix.sh
	@echo "✅ Attic client installed (Nix)"

attic-client-status:
	@echo "→ Attic client status"
	@if [ -x "$(ATTIC_CLIENT_BIN)" ]; then \
		echo "   • wrapper: $(ATTIC_CLIENT_BIN)"; \
	else \
		echo "   • wrapper: missing"; \
	fi
	@if test -x "$$(command -v nix)"; then \
		nix profile list | sed 's/^/   • profile: /' || true; \
	else \
		echo "   • nix: not installed"; \
	fi

remove-attic-client: ensure-run-as-root
	@echo "🗑️ Removing Attic client wrapper + stamp (Nix profile untouched)"
	@$(run_as_root) rm -f "$(ATTIC_CLIENT_BIN)"
	@echo "✅ Attic client wrapper removed"

.PHONY: ensure-nix-command

ensure-nix-command:
	@command -v nix >/dev/null 2>&1 || { \
		echo "[make] ❌ nix not found in PATH"; \
		echo "[make] → install Nix first"; \
		exit 1; \
	}
	@nix profile list >/dev/null 2>&1 || { \
		echo "[make] ❌ nix-command feature is disabled"; \
		echo "[make]"; \
		echo "[make] → run: make fix-nix-command"; \
		echo "[make] → or enable it manually in /etc/nix/nix.conf"; \
		exit 1; \
	}

.PHONY: fix-nix-command

fix-nix-command: ensure-run-as-root
	@echo "[make] → Enabling nix-command + flakes globally"

	@echo "[make] → Ensuring /etc/nix exists"
	@$(run_as_root) install -d -m 0755 /etc/nix

	@echo "[make] → Updating /etc/nix/nix.conf"
	@$(run_as_root) sh -c '\
		if [ -f /etc/nix/nix.conf ]; then \
			if grep -q "^experimental-features" /etc/nix/nix.conf; then \
				sed -i "s/^experimental-features.*/experimental-features = nix-command flakes/" /etc/nix/nix.conf; \
			else \
				echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf; \
			fi; \
		else \
			echo "experimental-features = nix-command flakes" > /etc/nix/nix.conf; \
		fi'

	@if systemctl list-unit-files nix-daemon.service >/dev/null 2>&1; then \
		echo "[make] → Restarting nix-daemon"; \
		$(run_as_root) systemctl restart nix-daemon; \
	else \
		echo "[make] → nix-daemon not present (single-user Nix)"; \
	fi

	@echo "[make] ✅ nix-command enabled"


.PHONY: attic-bootstrap-test
attic-bootstrap-test: ensure-run-as-root
	@echo "→ 1. Install Attic server + client"
	@$(run_as_root) "$(HOMELAB_DIR)/scripts/bootstrap-attic.sh"

	@echo "→ 2. Restart Attic service"
	@$(run_as_root) systemctl restart attic
	@sleep 2

	@echo "→ 3. Generate token"
	@TOKEN="$$(atticadm make-token \
		--sub homelab-client \
		--validity '3 months' \
		--create-cache homelab \
		--push homelab \
		--pull homelab)"; \
	echo "$$TOKEN" > $(HOMELAB_DIR)/attic-test.token; \
	echo "   Token saved to attic-test.token"

	@echo "→ 4. Login using token"
	@attic login homelab http://nas:8082 "$$(cat $(HOMELAB_DIR)/attic-test.token)"

	@echo "→ 5. Create cache"
	@attic cache create homelab || true

	@echo "→ 6. Download test file"
	@curl -fsSL https://nixos.org/logo/nix-logo.png -o /tmp/nix-logo.png

	@echo "→ 7. Push file into Attic"
	@HASH="$$(sha256sum /tmp/nix-logo.png | awk '{print $$1}')"; \
	attic push homelab $$HASH /tmp/nix-logo.png

	@echo "→ 8. Verify pull"
	@attic pull homelab $$HASH > /tmp/nix-logo-pulled.png

	@echo "✔ Attic end-to-end bootstrap test complete"
