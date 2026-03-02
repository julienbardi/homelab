# ============================================================
# mk/95_status.mk — System health (read-only, signal-first)
# ============================================================
# CONTRACT:
# - No mutation
# - No recursion
# - No installs
# - No restarts
# - Safe at any time
# ============================================================

.PHONY: status \
	status-kernel \
	status-firewall \
	status-wireguard \
	status-headscale \
	status-monitoring

status-kernel: ensure-run-as-root
	@ipv4=$$($(run_as_root) /sbin/sysctl -n net.ipv4.ip_forward); \
	ipv6=$$($(run_as_root) /sbin/sysctl -n net.ipv6.conf.all.forwarding); \
	if [ "$$ipv4" = "1" ] && [ "$$ipv6" = "1" ]; then \
	    echo "✅ Kernel forwarding enabled (IPv4 + IPv6)"; \
	else \
	    echo "❌ Kernel forwarding disabled"; exit 1; \
	fi

status-firewall:
	@if [ -f "$(HOMELAB_NFT_HASH_FILE)" ]; then \
	    echo "✅ nftables ruleset verified"; \
	else \
	    echo "❌ nftables ruleset not verified"; exit 1; \
	fi

status-wireguard:
	@count=$$(ip -o link show | awk -F': ' '/wg[0-9]+/{print $$2}' | wc -l); \
	if [ "$$count" -gt 0 ]; then \
	    echo "✅ WireGuard interfaces active: $$count"; \
	else \
	    echo "❌ No WireGuard interfaces active"; exit 1; \
	fi

status-headscale: ensure-run-as-root
	@if $(run_as_root) systemctl is-active --quiet headscale; then \
	    echo "✅ Headscale service active"; \
	else \
	    echo "❌ Headscale service inactive"; exit 1; \
	fi

status-monitoring: ensure-run-as-root
	@if $(run_as_root) systemctl is-active --quiet prometheus; then \
	    echo "✅ Prometheus running"; \
	else \
	    echo "❌ Prometheus not running"; exit 1; \
	fi

.PHONY: status
status: \
	status-kernel \
	status-firewall \
	status-wireguard \
	status-headscale \
	status-monitoring
	@echo ""
	@echo "🎉 System healthy"
