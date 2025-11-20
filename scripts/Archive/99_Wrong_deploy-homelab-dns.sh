#!/bin/bash
set -euo pipefail
source "/home/julie/homelab/scripts/config/homelab.env"

SERVICE_FILE=/etc/systemd/system/${DNSMASQ_SERVICE}

tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Homelab dnsmasq
After=network.target

[Service]
ExecStart=/usr/sbin/dnsmasq -k --conf-dir=${DNSMASQ_CONF_DIR} --port=${DNSMASQ_PORT}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable --now "${DNSMASQ_SERVICE}"
