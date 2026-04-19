# mk/06_acme_timer.mk
# ------------------------------------------------------------
# ACME Renewal Timer (Systemd) - IDEMPOTENT VERSION
# ------------------------------------------------------------

ACME_BIN  := /var/lib/acme/acme.sh
ACME_HOME := /var/lib/acme

.PHONY: acme-timer-install
acme-timer-install: ensure-run-as-root
	@$(run_as_root) bash -c ' \
		SERVICE_CONTENT="[Unit]\nDescription=Renew ACME Certificates\nAfter=network-online.target\n\n[Service]\nType=oneshot\nExecStart=$(ACME_BIN) --cron --home $(ACME_HOME)\nUser=root\nGroup=root"; \
		TIMER_CONTENT="[Unit]\nDescription=Daily ACME Certificate Renewal Check\n\n[Timer]\nOnCalendar=*-*-* 00:00:00\nRandomizedDelaySec=1h\nPersistent=true\n\n[Install]\nWantedBy=timers.target"; \
		\
		CHANGED=0; \
		if [ "$$(printf "$$SERVICE_CONTENT")" != "$$(cat /etc/systemd/system/acme-renewal.service 2>/dev/null)" ]; then \
			printf "⏱️  Updating ACME service unit...\n"; \
			printf "$$SERVICE_CONTENT" > /etc/systemd/system/acme-renewal.service; \
			CHANGED=1; \
		fi; \
		if [ "$$(printf "$$TIMER_CONTENT")" != "$$(cat /etc/systemd/system/acme-renewal.timer 2>/dev/null)" ]; then \
			printf "⏱️  Updating ACME timer unit...\n"; \
			printf "$$TIMER_CONTENT" > /etc/systemd/system/acme-renewal.timer; \
			CHANGED=1; \
		fi; \
		\
		if [ $$CHANGED -eq 1 ]; then \
			systemctl daemon-reload; \
			systemctl enable --now acme-renewal.timer; \
			echo "$(SUCCESS_ICON) ACME systemd timer updated and active."; \
		else \
			echo "$(INFO_ICON) ACME systemd timer is already up-to-date."; \
		fi'