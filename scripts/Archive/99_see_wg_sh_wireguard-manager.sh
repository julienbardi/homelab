#!/bin/bash
set -euo pipefail
source "/home/julie/homelab/scripts/config/homelab.env"

REGISTRY="$CLIENTS_DIR/registry.csv"
WG_CONF="$WG_DIR/${WG_INTERFACE}.conf"

usage() {
  echo "Usage: $0 {init-server|add-client <name>|list|remove-client <name>}"
  exit 1
}

init_server() {
  mkdir -p "$CLIENTS_DIR"
  touch "$REGISTRY"

  if [[ -f "$WG_SERVER_KEY" ]]; then
    echo "⚠️  Server key already exists at $WG_SERVER_KEY"
  else
    umask 077
    wg genkey | tee "$WG_SERVER_KEY" | wg pubkey > "${WG_SERVER_KEY}.pub"
    echo "✅ Generated new server keypair"
  fi

  SERVER_PRIV=$(cat "$WG_SERVER_KEY")
  SERVER_PUB=$(cat "${WG_SERVER_KEY}.pub")

  cat > "$WG_CONF" <<EOF
[Interface]
Address = $(echo $WG_SUBNET | sed 's|0/24|1/24|')
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
EOF

  systemctl enable --now wg-quick@${WG_INTERFACE}
  echo "✅ WireGuard server initialized on $WG_INTERFACE"
}

add_client() {
  NAME=$1
  if grep -q "^$NAME," "$REGISTRY" 2>/dev/null; then
    echo "❌ Client $NAME already exists in registry"
    exit 1
  fi

  umask 077
  CLIENT_PRIV=$(wg genkey)
  CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
  CLIENT_IP=$(awk -F, 'END {if (NR==0) print "10.4.0.2"; else {split($3,a,"."); print a[1]"."a[2]"."a[3]"."a[4]+1}}' "$REGISTRY")

  echo "$NAME,$CLIENT_PUB,$CLIENT_IP" >> "$REGISTRY"

  # Append to server config with markers
  {
    echo "# $NAME BEGIN"
    echo "[Peer]"
    echo "PublicKey = $CLIENT_PUB"
    echo "AllowedIPs = $CLIENT_IP/32"
    echo "# $NAME END"
  } >> "$WG_CONF"

  wg set $WG_INTERFACE peer "$CLIENT_PUB" allowed-ips "$CLIENT_IP/32"

  # Generate client config
  CLIENT_CONF="$CLIENTS_DIR/${NAME}.conf"
  SERVER_PUB=$(cat "${WG_SERVER_KEY}.pub")
  SERVER_IP=$(echo $WG_SUBNET | sed 's|0/24|1|')

  cat > "$CLIENT_CONF" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/32
DNS = 192.168.50.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $(hostname -I | awk '{print $1}'):$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

  qrencode -t ansiutf8 < "$CLIENT_CONF"

  echo "✅ Added client $NAME with IP $CLIENT_IP"
}

list_clients() {
  if [[ ! -f "$REGISTRY" ]]; then
    echo "No clients registered"
    exit 0
  fi
  column -t -s, "$REGISTRY"
}

remove_client() {
  NAME=$1
  if ! grep -q "^$NAME," "$REGISTRY"; then
    echo "❌ Client $NAME not found"
    exit 1
  fi

  CLIENT_PUB=$(grep "^$NAME," "$REGISTRY" | cut -d, -f2)

  # Remove from registry
  grep -v "^$NAME," "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"

  # Remove from server config
  sed -i "/# $NAME BEGIN/,/# $NAME END/d" "$WG_CONF"

  # Remove live peer
  wg set $WG_INTERFACE peer "$CLIENT_PUB" remove || true

  echo "✅ Removed client $NAME"
}

case "${1:-}" in
  init-server) init_server ;;
  add-client) [[ $# -eq 2 ]] || usage; add_client "$2" ;;
  list) list_clients ;;
  remove-client) [[ $# -eq 2 ]] || usage; remove_client "$2" ;;
  *) usage ;;
esac
