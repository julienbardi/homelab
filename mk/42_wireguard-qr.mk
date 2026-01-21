# mk/42_wireguard-qr.mk
# ============================================================
# WireGuard client display helpers
# ============================================================

WG_EXPORT_ROOT := /volume1/homelab/wireguard/export/clients
WG_QR := /usr/local/bin/wg-qr.sh

.PHONY: wg-show wg-qr

# Show client config + QR
# Usage: make wg-show BASE=julie-s22 IFACE=wg7
wg-show: $(WG_QR)
	@if [ -z "$(BASE)" ] || [ -z "$(IFACE)" ]; then \
		echo "Usage: make wg-show BASE=<base> IFACE=<wgX>"; exit 1; \
	fi
	@echo "🔐 Showing WireGuard client config + QR"
	@$(run_as_root) sh -euc '\
		conf="$(WG_EXPORT_ROOT)/$(BASE)/$(IFACE).conf"; \
		[ -f "$$conf" ] || { echo "Missing $$conf"; exit 1; }; \
		cat "$$conf"; \
		echo ""; \
		$(WG_QR) "$$conf" "$${conf%.conf}.png" \
	'

# Show QR only
# Usage: make wg-qr BASE=julie-s22 IFACE=wg7
wg-qr: $(WG_QR)
	@if [ -z "$(BASE)" ] || [ -z "$(IFACE)" ]; then \
		echo "Usage: make wg-qr BASE=<base> IFACE=<wgX>"; exit 1; \
	fi
	@echo "📱 Generating WireGuard QR code"
	@$(run_as_root) sh -euc '\
		conf="$(WG_EXPORT_ROOT)/$(BASE)/$(IFACE).conf"; \
		[ -f "$$conf" ] || { echo "Missing $$conf"; exit 1; }; \
		$(WG_QR) "$$conf" "$${conf%.conf}.png" \
	'
