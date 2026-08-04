# ============================================================
<<<<<<< HEAD
# mk/11_permissions.mk — Homelab directory + WireGuard input perms
# ============================================================

WG_INPUT_DIR := /var/lib/homelab/wireguard/input

.PHONY: enforce-homelab-perms
enforce-homelab-perms:
	@echo " Enforcing homelab directory permissions"
	$(run_as_root) chown -R root:admins /var/lib/homelab
	$(run_as_root) chmod -R 770 /var/lib/homelab

.PHONY: enforce-wireguard-input
enforce-wireguard-input:
	@echo " Enforcing WireGuard input directory permissions"
	$(run_as_root) mkdir -p $(WG_INPUT_DIR)
	$(run_as_root) chown root:admins $(WG_INPUT_DIR)
	$(run_as_root) chmod 770 $(WG_INPUT_DIR)
	@# Fix file permissions inside
	$(run_as_root) find $(WG_INPUT_DIR) -type f -exec chown root:admins {} \;
	$(run_as_root) find $(WG_INPUT_DIR) -type f -exec chmod 660 {} \;
=======
# mk/11_permissions.mk — Admin RW access to sensitive files
# ============================================================

WG_INPUT := /root/src/homelab/wireguard/input/wg-interfaces.tsv

.PHONY: enforce-wg-permissions
enforce-wg-permissions: enforce-groups
	@# Ensure file exists before applying permissions
	@if [ ! -f "$(WG_INPUT)" ]; then \
		echo "⚠️ $(WG_INPUT) missing — skipping permission fix"; \
		exit 0; \
	fi

	@echo "🔐 Setting admins RW access on $(WG_INPUT)"
	$(run_as_root) chown root:admins "$(WG_INPUT)"
	$(run_as_root) chmod 660 "$(WG_INPUT)"
>>>>>>> 95cd370 (Add admin permission enforcement for WG input file and integrate into build DAG)
