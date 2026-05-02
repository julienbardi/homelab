# mk/06_acme_timer.mk
# ------------------------------------------------------------
# ACME Renewal Timer (Systemd) - IDEMPOTENT VERSION
# ------------------------------------------------------------

ACME_BIN  := /var/lib/acme/acme.sh
ACME_HOME := /var/lib/acme

SERVICE_FILE := /etc/systemd/system/acme-renewal.service
TIMER_FILE   := /etc/systemd/system/acme-renewal.timer

SERVICE_CONTENT := [Unit]\
\nDescription=Renew ACME Certificates\
\nAfter=network-online.target\
\n\
\n[Service]\
\nType=oneshot\
\nExecStart=$(ACME_BIN) --cron --home $(ACME_HOME)\
\nUser=root\
\nGroup=root

TIMER_CONTENT := [Unit]\
\nDescription=Daily ACME Certificate Renewal Check\
\n\
\n[Timer]\
\nOnCalendar=*-*-* 00:00:00\
\nRandomizedDelaySec=1h\
\nPersistent=true\
\n\
\n[Install]\
\nWantedBy=timers.target

.PHONY: acme-timer-install
acme-timer-install: ensure-run-as-root
	@CHANGED=0; \
	if [ "$$(printf "$(SERVICE_CONTENT)")" != "$$(cat $(SERVICE_FILE) 2>/dev/null)" ]; then \
		echo "⏱️  Updating ACME service unit..."; \
		printf "$(SERVICE_CONTENT)" | $(run_as_root) tee $(SERVICE_FILE) >/dev/null; \
		CHANGED=1; \
	fi; \
	if [ "$$(printf "$(TIMER_CONTENT)")" != "$$(cat $(TIMER_FILE) 2>/dev/null)" ]; then \
		echo "⏱️  Updating ACME timer unit..."; \
		printf "$(TIMER_CONTENT)" | $(run_as_root) tee $(TIMER_FILE) >/dev/null; \
		CHANGED=1; \
	fi; \
	if [ $$CHANGED -eq 1 ]; then \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) systemctl enable --now acme-renewal.timer; \
		echo "$(SUCCESS_ICON) ACME systemd timer updated and active."; \
	else \
		echo "$(INFO_ICON) ACME systemd timer is already up-to-date."; \
	fi
