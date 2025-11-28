# ============================================================
# mk/unbound.mk — Unbound orchestration
# ============================================================

.PHONY: deploy-unbound-config deploy-unbound-service deploy-unbound

UNBOUND_CONF_SRC := /home/julie/src/homelab/config/unbound/unbound.conf
UNBOUND_CONF_DST := /etc/unbound/unbound.conf

deploy-unbound-config:
	@echo "[make] Deploying unbound.conf from Git → /etc"
	@sudo install -d -m 0755 /etc/unbound
	@sudo install -m 0644 $(UNBOUND_CONF_SRC) $(UNBOUND_CONF_DST)
	@sudo chown root:root $(UNBOUND_CONF_DST)
	@sudo mkdir -p /run/unbound/unbound
	@sudo chown unbound:unbound /run/unbound/unbound
	@sudo unbound-checkconf $(UNBOUND_CONF_DST) || { echo "[make] ❌ unbound.conf invalid"; exit 1; }
	@echo "[make] ✅ unbound.conf deployed successfully"

UNBOUND_SERVICE_SRC := /home/julie/src/homelab/config/systemd/unbound.service
UNBOUND_SERVICE_DST := /etc/systemd/system/unbound.service

deploy-unbound-service:
	@echo "[make] Deploying unbound.service from Git → /etc/systemd/system"
	@sudo install -m 0644 $(UNBOUND_SERVICE_SRC) $(UNBOUND_SERVICE_DST)
	@sudo chown root:root $(UNBOUND_SERVICE_DST)
	@sudo systemctl daemon-reload
	@echo "[make] ✅ unbound.service deployed successfully"

deploy-unbound: deploy-unbound-config deploy-unbound-service
	@echo "[make] Restarting unbound service"
	@sudo systemctl enable --now unbound || { echo "[make] ❌ failed to enable unbound"; exit 1; }
	@sudo systemctl restart unbound || { echo "[make] ❌ failed to restart unbound"; exit 1; }
	@sudo systemctl status --no-pager unbound

.PHONY: setup-unbound-control

setup-unbound-control:
	@echo "[make] Setting up Unbound remote-control interface"
	@sudo unbound-control-setup || { echo "[make] ❌ unbound-control-setup failed"; exit 1; }
	@sudo chown unbound:unbound /etc/unbound/unbound_*.{key,pem}
	@sudo chmod 0640 /etc/unbound/unbound_*.{key,pem}
	@sudo systemctl restart unbound || { echo "[make] ❌ failed to restart unbound"; exit 1; }
	@echo "[make] ✅ Unbound remote-control interface initialized"
	@echo "[make] Testing unbound-control connectivity..."
	@sudo unbound-control status || { echo "[make] ❌ unbound-control not responding"; exit 1; }
	@echo "[make] ✅ unbound-control is responding"
