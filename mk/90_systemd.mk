# 90_systemd.mk — Systemd unit management for homelab services

SYSTEMD_DIR    := /etc/systemd/system
REPO_SYSTEMD   := config/systemd

# ------------------------------------------------------------
# Per‑unit installers (explicit, privilege‑correct)
# ------------------------------------------------------------

.PHONY: install-dns-health
install-dns-health: ensure-run-as-root
	@$(run_as_root) install -m 0644 -o root -g root \
		$(REPO_ROOT)/$(REPO_SYSTEMD)/homelab-dns-health.service \
		$(SYSTEMD_DIR)/homelab-dns-health.service

.PHONY: install-nas-prefix-watchdog
install-nas-prefix-watchdog: ensure-run-as-root
	@echo "🧩 Installing NAS IPv6 prefix watchdog"

	# Install script
	$(run_as_root) install -m 755 $(REPO_ROOT)/scripts/homelab-prefix-converge.sh /usr/local/bin/

	# Install systemd unit + timer
	$(run_as_root) install -m 644 $(REPO_ROOT)/config/systemd/homelab-prefix-converge.service /etc/systemd/system/
	$(run_as_root) install -m 644 $(REPO_ROOT)/config/systemd/homelab-prefix-converge.timer /etc/systemd/system/

	# Reload systemd and enable timer
	$(run_as_root) systemctl daemon-reload
	$(run_as_root) systemctl enable --now homelab-prefix-converge.timer

# ------------------------------------------------------------
# Umbrella systemd installer
# ------------------------------------------------------------

.PHONY: install-systemd enable-systemd verify-systemd uninstall-systemd

install-systemd: ensure-run-as-root install-dns-health
	@echo "🧩 Installing systemd units"
	@if [ ! -d "$(REPO_ROOT)/$(REPO_SYSTEMD)" ]; then \
		echo "ERROR: $(REPO_ROOT)/$(REPO_SYSTEMD) not found"; exit 1; \
	fi
	@$(run_as_root) sh -c '\
		mkdir -p $(SYSTEMD_DIR); \
		\
		# --- fix vendor-broken index_serv.service --- \
		mkdir -p $(SYSTEMD_DIR)/index_serv.service.d; \
		install -o root -g root -m 0644 \
			$(REPO_ROOT)/$(REPO_SYSTEMD)/index_serv.service.d/10-fix-output.conf \
			$(SYSTEMD_DIR)/index_serv.service.d/10-fix-output.conf; \
		\
		systemctl daemon-reload; \
	'

# ------------------------------------------------------------
# Enable + start services
# ------------------------------------------------------------

enable-systemd: install-systemd ensure-run-as-root
	@$(run_as_root) sh -c '\
		if systemctl is-active --quiet homelab-unbound.service; then \
			echo "🟢 homelab-unbound.service already running and converged"; \
		else \
			echo "🚀 Starting homelab-unbound.service (was not active)"; \
			systemctl start homelab-unbound.service || true; \
		fi; \
	'

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------

verify-systemd: ensure-run-as-root
	@echo "🔍 Status and socket ownership:"
	@$(run_as_root) systemctl status unbound --no-pager || true

# ------------------------------------------------------------
# Uninstall (minimal)
# ------------------------------------------------------------

uninstall-systemd: ensure-run-as-root
	@$(run_as_root) systemctl daemon-reload >/dev/null 2>&1 || true
