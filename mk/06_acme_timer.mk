# mk/06_acme_timer.mk
# ------------------------------------------------------------
# ACME Renewal Timer (Systemd)
# ------------------------------------------------------------

ACME_BIN := /var/lib/acme/acme.sh
ACME_HOME := /var/lib/acme

.PHONY: acme-timer-install
acme-timer-install: ensure-run-as-root
	@echo "⏱️  Installing ACME renewal systemd units..."
	@$(run_as_root) bash -c 'cat <<EOF > /etc/systemd/system/acme-renewal.service
[Unit]
Description=Renew ACME Certificates
After=network-online.target

[Service]
Type=oneshot
ExecStart=$(ACME_BIN) --cron --home $(ACME_HOME)
User=root
Group=root
EOF'
	@$(run_as_root) bash -c 'cat <<EOF > /etc/systemd/system/acme-renewal.timer
[Unit]
Description=Daily ACME Certificate Renewal Check

[Timer]
OnCalendar=*-*-* 00:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF'
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable --now acme-renewal.timer
	@echo "✅ ACME systemd timer is active."