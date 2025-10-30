SHELL := /bin/bash
SCRIPTS := /home/julie/homelab/scripts
ENV := $(SCRIPTS)/config/homelab.env

.PHONY: all init-dirs setup dnsmasq firewall wireguard tailscale headscale certs status clean reset-state \
        wireguard-init wireguard-add wireguard-list wireguard-remove \
        headscale-list headscale-new headscale-revoke headscale-show headscale-qr \
        certs-issue certs-deploy certs-validate certs-all \
        subnet-router-service aliases

# Init dirs
init-dirs:
    @bash -c 'source "$(ENV)"; \
      sudo mkdir -p "$${WG_DIR}" "$${CLIENTS_DIR}" "$${SSL_DEPLOY_DIR_HEADSCALE}" "$${DNSMASQ_CONF_DIR}"; \
      sudo chmod 700 "$${WG_DIR}" "$${CLIENTS_DIR}"; \
      sudo chmod 755 "$${SSL_DEPLOY_DIR_HEADSCALE}"; \
      sudo touch /var/lib/homelab-version'

all: init-dirs setup dnsmasq firewall wireguard tailscale headscale certs subnet-router-service aliases

setup:
    sudo $(SCRIPTS)/setup-homelab.sh

dnsmasq:
    sudo $(SCRIPTS)/deploy-homelab-dns.sh

firewall:
    sudo $(SCRIPTS)/firewall.sh

# WireGuard
wireguard-init:
    sudo $(SCRIPTS)/wireguard-manager.sh init-server

wireguard-add:
    sudo $(SCRIPTS)/wireguard-manager.sh add-client $$NAME

wireguard-list:
    sudo $(SCRIPTS)/wireguard-manager.sh list

wireguard-remove:
    sudo $(SCRIPTS)/wireguard-manager.sh remove-client $$NAME

# Tailscale / Headscale
tailscale:
    sudo $(SCRIPTS)/setup-tailscale-client.sh

headscale-new:
    sudo $(SCRIPTS)/headscale-keys.sh new $$NAME

headscale-list:
    sudo $(SCRIPTS)/headscale-keys.sh list

headscale-revoke:
    sudo $(SCRIPTS)/headscale-keys.sh revoke $$ARG

headscale-show:
    sudo $(SCRIPTS)/headscale-keys.sh show $$NAME

headscale-qr:
    sudo $(SCRIPTS)/headscale-keys.sh qr $$NAME

# Certificates
certs-issue:
    sudo $(SCRIPTS)/bardi_cert.sh issue

certs-deploy:
    sudo $(SCRIPTS)/bardi_cert.sh deploy headscale

certs-validate:
    sudo $(SCRIPTS)/bardi_cert.sh validate

certs-all:
    sudo $(SCRIPTS)/bardi_cert.sh all headscale

# Status / Cleanup
status:
    sudo $(SCRIPTS)/setup-homelab.sh --status

clean:
    sudo rm -f /var/lib/homelab-version
    @bash -c 'source "$(ENV)"; sudo rm -f "$${CLIENTS_DIR}/registry.csv"'

reset-state: clean
    @bash -c 'source "$(ENV)"; \
      sudo systemctl stop wg-quick@$$WG_INTERFACE || true; \
      sudo rm -f "$${WG_DIR}"/*.conf; \
      sudo rm -rf "$${CLIENTS_DIR}"/*; \
      sudo rm -f "$${SSL_DEPLOY_DIR_HEADSCALE}"/*; \
    '

# Subnet Router
subnet-router-service:
    sudo cp $(SCRIPTS)/systemd/subnet-router.service /etc/systemd/system/subnet-router.service
    sudo cp $(SCRIPTS)/setup-subnet-router.sh /usr/local/bin/setup-subnet-router.sh
    sudo chmod +x /usr/local/bin/setup-subnet-router.sh
    sudo systemctl daemon-reload
    sudo systemctl enable --now subnet-router.service

# Aliases
ALIASES_FILE := /home/julie/.bashrc

aliases:
    @echo "📦 Installing router aliases into $(ALIASES_FILE)..."
    @grep -qxF "alias router-logs='journalctl -u subnet-router.service -f -n 50'" $(ALIASES_FILE) || \
      echo "alias router-logs='journalctl -u subnet-router.service -f -n 50'" | sudo tee -a $(ALIASES_FILE) >/dev/null
    @grep -qxF "alias router-deploy='sudo cp /home/julie/homelab/scripts/setup-subnet-router.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/setup-subnet-router.sh && sudo systemctl restart subnet-router.service'" $(ALIASES_FILE) || \
      echo "alias router-deploy='sudo cp /home/julie/homelab/scripts/setup-subnet-router.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/setup-subnet-router.sh && sudo systemctl restart subnet-router.service'" | sudo tee -a $(ALIASES_FILE) >/dev/null
    @echo "✅ Aliases installed into $(ALIASES_FILE)"
    @echo "📢 Reloading shell configuration..."
    @. $(ALIASES_FILE) || true
