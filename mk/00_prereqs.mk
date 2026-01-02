# mk/00_prereqs.mk
.PHONY: prereqs

# ------------------------------------------------------------
# Core tooling used across scripts
# ------------------------------------------------------------
prereqs:
	@echo "[make] Ensuring installation of prerequisite tools"
	@$(call apt_update_if_needed)
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		build-essential \
		curl jq git nftables iptables shellcheck pup codespell aspell ndppd \
		knot-dnsutils \
		iperf3 qrencode \
		libc-ares-dev
	@echo "✅ [make] Base prerequisites installed"