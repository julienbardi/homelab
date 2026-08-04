# ============================================================
# mk/11_permissions.mk — Homelab directory + WireGuard input perms
# ============================================================

# --------------------------------------------------------------------
# Enforce homelab directory permissions (root:admins, 770)
# --------------------------------------------------------------------
.PHONY: enforce-homelab-perms
enforce-homelab-perms: enforce-groups
	@echo "🔐 Enforcing homelab directory permissions"
	$(run_as_root) sh -c '\
		install -d -m 770 -o root -g admins /var/lib/homelab && \
		chown -R root:admins /var/lib/homelab && \
		chmod -R 770 /var/lib/homelab \
	'

.PHONY: enforce-wireguard-input
enforce-wireguard-input: enforce-groups
	@echo "🔐 Enforcing WireGuard input directory + file permissions"
	$(run_as_root) sh -c '\
		install -d -m 770 -o root -g admins "$(WG_INPUT_DIR)" && \
		chown -R root:admins "$(WG_INPUT_DIR)" && \
		find "$(WG_INPUT_DIR)" -type f -exec chmod 660 {} + \
	'
