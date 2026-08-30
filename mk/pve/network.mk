# mk/pve/network.mk
# ------------------------------------------------------------
# PROXMOX VE NETWORK VALIDATION
# ------------------------------------------------------------

.PHONY: pve-network-validate
pve-network-validate: router-provision-nvram
	@echo "🔍 Validating Proxmox VE network configuration comprehensively..."
	@set -e; \
	interfaces_file="/etc/network/interfaces"; \
	if [ ! -f "$$interfaces_file" ]; then \
		echo "❌ Network interfaces file not found: $$interfaces_file"; \
		exit 1; \
	fi; \
	\
	# --- IPv4 Validation --- \
	grep -qE "^[[:space:]]*iface[[:space:]]+$(NAS_LAN_IFACE)[[:space:]]+inet[[:space:]]+static" "$$interfaces_file" || { echo "❌ $(NAS_LAN_IFACE) missing inet static block"; exit 1; }; \
	grep -qE "^[[:space:]]+address[[:space:]]+10\.89\.12\.4/24" "$$interfaces_file" || { echo "❌ $(NAS_LAN_IFACE) IPv4 address mismatch"; exit 1; }; \
	grep -qE "^[[:space:]]+gateway[[:space:]]+10\.89\.12\.1" "$$interfaces_file" || { echo "❌ $(NAS_LAN_IFACE) IPv4 gateway mismatch"; exit 1; }; \
	grep -qE "^[[:space:]]+bridge-ports[[:space:]]+nic1" "$$interfaces_file" || { echo "❌ $(NAS_LAN_IFACE) bridge-ports mismatch"; exit 1; }; \
	\
	# --- IPv6 ULA Validation --- \
	grep -qE "^[[:space:]]*iface[[:space:]]+$(NAS_LAN_IFACE)[[:space:]]+inet6[[:space:]]+static" "$$interfaces_file" || { echo "❌ $(NAS_LAN_IFACE) missing inet6 static block"; exit 1; }; \
	grep -qE "^[[:space:]]+address[[:space:]]+$(LAN6_NAS)/64" "$$interfaces_file" || { echo "❌ $(NAS_LAN_IFACE) IPv6 ULA address mismatch"; exit 1; }; \
	grep -qE "^[[:space:]]+gateway[[:space:]]+$(LAN6_ROUTER)" "$$interfaces_file" || { echo "❌ $(NAS_LAN_IFACE) IPv6 ULA gateway mismatch"; exit 1; }; \
	\
	echo "🟢 Proxmox VE network configuration validated successfully (IPv4 and IPv6 ULA)"