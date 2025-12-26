# mk/00_prereqs.mk
.PHONY: prereqs prereqs-tools prereqs-dns prereqs-dev

prereqs: prereqs-tools prereqs-dns prereqs-dev
	@echo "✅ [make] Base prerequisites installed"

# ------------------------------------------------------------
# Core tooling used across scripts
# ------------------------------------------------------------
prereqs-tools:
	@echo "[make] Ensuring base tools"
	@sudo apt-get update
	@sudo apt-get install -y \
		curl \
		jq \
		git \
		nftables \
		iptables \
		shellcheck \
		pup

# ------------------------------------------------------------
# DNS / networking diagnostics
# ------------------------------------------------------------
prereqs-dns:
	@echo "[make] Ensuring DNS tooling"
	@if command -v kdig >/dev/null 2>&1; then \
		echo "[make] kdig already installed"; \
	else \
		sudo apt-get install -y knot-dnsutils; \
	fi

# ------------------------------------------------------------
# Developer / admin helpers
# ------------------------------------------------------------
prereqs-dev:
	@echo "[make] Ensuring admin helpers"
	@sudo apt-get install -y \
		iperf3 \
		qrencode
