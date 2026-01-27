# mk/42_wireguard-qr.mk
# ============================================================
# WireGuard client display helpers
# ============================================================

WG_EXPORT_ROOT := $(WG_ROOT)/export/clients
WG_QR := /usr/local/bin/wg-qr.sh

.PHONY: wg-show wg-qr

# Show client config + QR
# Usage: make wg-show BASE=julie-s22 IFACE=wg7
wg-show: ensure-run-as-root $(WG_QR)
	@if [ -z "$(BASE)" ] || [ -z "$(IFACE)" ]; then \
		echo "Usage: make wg-show BASE=<base> IFACE=<wgX>"; exit 1; \
	fi
	@$(run_as_root) sh -euc '\
		conf="$(WG_EXPORT_ROOT)/$(BASE)/$(IFACE).conf"; \
		[ -f "$$conf" ] || { echo "Missing $$conf"; exit 1; }; \
		cat "$$conf"; \
	'

# Show QR only
# Usage: make wg-qr BASE=julie-s22 IFACE=wg7
wg-qr: ensure-run-as-root $(WG_QR)
	@if [ -z "$(BASE)" ] || [ -z "$(IFACE)" ]; then \
		echo "Usage: make wg-qr BASE=<base> IFACE=<wgX>"; exit 1; \
	fi
	@echo "📱 Generating WireGuard QR code"
	@$(run_as_root) sh -euc '\
		conf="$(WG_EXPORT_ROOT)/$(BASE)/$(IFACE).conf"; \
		[ -f "$$conf" ] || { echo "Missing $$conf"; exit 1; }; \
		$(WG_QR) "$$conf" "$${conf%.conf}.png" \
	'
