#!/bin/bash
set -euo pipefail
SCRIPT_NAME="unbound-setup-control"
source /usr/local/bin/common.sh

require_bin unbound-control-setup "Required for Unbound remote control"

if [ ! -f /etc/unbound/unbound_server.key ]; then
    log "📦 Generating control certificates"
    unbound-control-setup
fi

log "🔐 Fixing ownership and permissions"
chown root:unbound /etc/unbound
chmod 0755 /etc/unbound
install -m 0640 -o root -g unbound /etc/unbound/unbound_{server,control}.{key,pem} /etc/unbound/

log "📝 Writing unbound-control.conf"
cat >/etc/unbound/unbound-control.conf <<'EOF'
remote-control:
    control-interface: /run/unbound.ctl
    server-key-file: /etc/unbound/unbound_server.key
    server-cert-file: /etc/unbound/unbound_server.pem
    control-key-file: /etc/unbound/unbound_control.key
    control-cert-file: /etc/unbound/unbound_control.pem
EOF

log "🔄 Restarting unbound"
systemctl restart unbound

sleep 2

if [ ! -S /run/unbound.ctl ]; then
    log "❌ control socket missing"
    journalctl -u unbound -n 200 --no-pager
    exit 1
fi

log "✅ unbound-control ready"
