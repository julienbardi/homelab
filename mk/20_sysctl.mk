# mk/20_sysctl.mk
.PHONY: install-homelab-sysctl

install-homelab-sysctl:
	@echo "🧩 Installing homelab sysctl forwarding config"
	$(run_as_root) install -o root -g root -m 0644 \
		config/sysctl.d/99-homelab-forwarding.conf \
		/etc/sysctl.d/99-homelab-forwarding.conf
	$(run_as_root) sysctl --system
	@echo "✅ Kernel forwarding enabled (IPv4 + IPv6)"
