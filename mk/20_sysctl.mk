# mk/20_sysctl.mk
.PHONY: install-homelab-sysctl

install-homelab-sysctl:
	@echo "🧩 Installing homelab sysctl forwarding config"
	@set -eu; \
	src="config/sysctl.d/99-homelab-forwarding.conf"; \
	dst="/etc/sysctl.d/99-homelab-forwarding.conf"; \
	tmp="$${dst}.tmp.$$"; \
	changed=0; \
	$(run_as_root) install -o root -g root -m 0644 "$$src" "$$tmp"; \
	if [ ! -f "$$dst" ]; then \
		changed=1; \
	elif ! $(run_as_root) cmp -s "$$tmp" "$$dst"; then \
		changed=1; \
	fi; \
	if [ "$$changed" -eq 1 ]; then \
		$(run_as_root) install -o root -g root -m 0644 "$$tmp" "$$dst"; \
		$(run_as_root) sysctl --system; \
		echo "🔄 Kernel forwarding applied (config changed)"; \
	else \
		echo "⚪ Kernel forwarding unchanged (already converged)"; \
	fi; \
	$(run_as_root) rm -f "$$tmp"
