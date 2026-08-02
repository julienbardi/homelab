# ============================================================
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
