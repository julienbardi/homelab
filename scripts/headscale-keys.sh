#!/bin/bash
#
# headscale-keys.sh — Manage Headscale pre-auth keys (tag-based, no local storage)
#
# Usage:
#   headscale-keys.sh new <machine>     # create new 24h reusable key tagged with machine
#   headscale-keys.sh list              # list all keys with full table output
#   headscale-keys.sh revoke <arg>      # revoke key by machine tag or numeric ID
#   headscale-keys.sh qr <machine>      # show QR code for machine key
#   headscale-keys.sh show <machine>    # display raw key string
#

set -euo pipefail

NAMESPACE="homelab"   # change if you want another namespace
HOST="nas.bardi.ch"
PORT=8443

# Decide scheme based on port
scheme="https"
if [[ "$PORT" == "80" || "$PORT" == "8080" ]]; then
  scheme="http"
fi

# --- Auto-detect namespace support and existence ---
if headscale preauthkeys list --user "$NAMESPACE" --output json >/dev/null 2>&1; then
  USER_FLAG=(--user "$NAMESPACE")
  echo "ℹ️ Using namespace name: $NAMESPACE"
else
  # Force null → [] so jq never crashes
  NS_JSON=$(headscale namespaces list --output json 2>/dev/null | jq 'if . == null then [] else . end')
  NS_ID=$(echo "$NS_JSON" | jq -r --arg ns "$NAMESPACE" '.[] | select(.name==$ns) | .id')

  if [[ -z "$NS_ID" || "$NS_ID" == "null" ]]; then
    echo "⚠️ Namespace '$NAMESPACE' not found."
    read -rp "Do you want to create it now? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      sudo headscale namespaces create "$NAMESPACE"
      NS_ID=$(headscale namespaces list --output json | jq -r --arg ns "$NAMESPACE" '.[] | select(.name==$ns) | .id')
      echo "✅ Created namespace '$NAMESPACE' (ID: $NS_ID)"
    else
      echo "ERROR: Namespace '$NAMESPACE' is required. Exiting."
      exit 1
    fi
  fi

  USER_FLAG=(--user "$NS_ID")
fi

usage() {
  echo "Usage: $0 {new <machine>|list|revoke <machine|id>|qr <machine>|show <machine>}"
  exit 1
}

check_tls_cert() {
  if [[ "$scheme" == "http" ]]; then
    echo "Skipping TLS certificate check ($scheme mode on port $PORT)"
    return
  fi
  echo "Checking TLS certificate for $scheme://$HOST:$PORT ..."
  if ! timeout 5 openssl s_client -connect ${HOST}:${PORT} -servername ${HOST} </dev/null 2>/dev/null \
     | openssl x509 -noout -dates -subject >/tmp/headscale-cert.$$; then
    echo "ERROR: Could not retrieve TLS certificate from $HOST:$PORT"
    exit 1
  fi
  notAfter=$(grep notAfter /tmp/headscale-cert.$$ | cut -d= -f2-)
  expiry_epoch=$(date -d "$notAfter" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$notAfter" +%s)
  now_epoch=$(date +%s)
  if [ "$expiry_epoch" -le "$now_epoch" ]; then
    echo "ERROR: TLS certificate expired ($notAfter)."
    rm -f /tmp/headscale-cert.$$
    exit 1
  fi
  echo "TLS certificate valid until: $notAfter"
  rm -f /tmp/headscale-cert.$$
}

cmd="${1:-}"
arg="${2:-}"
case "$cmd" in
  new)
    [ -z "$arg" ] && usage
    check_tls_cert
    key=$(sudo headscale preauthkeys create \
      "${USER_FLAG[@]}" --reusable --expiration 24h \
      --tags "tag:machine:${arg}" \
      --output json | jq -r '.key')
    if [ "$key" = "null" ] || [ -z "$key" ]; then
      echo "ERROR: Failed to obtain a preauth key."
      exit 1
    fi
    echo "👉 On Windows 11 (PowerShell as Administrator) client (on linux add sudo as prefix) , run:"
    echo "    tailscale up --login-server=$scheme://$HOST:$PORT --authkey=$key"
    echo "👉 On mobile, scan this QR code obtained using $0 qr $arg"
    echo "$key" | qrencode -t ansiutf8
    ;;
  list)
    sudo headscale preauthkeys list "${USER_FLAG[@]}"
    ;;
  revoke)
    [ -z "$arg" ] && usage
    if [[ "$arg" =~ ^[0-9]+$ ]]; then
      key=$(sudo headscale preauthkeys list "${USER_FLAG[@]}" --output json \
        | jq -r --arg id "$arg" '.[] | select((.id|tostring) == $id) | .key')
      [ -z "$key" ] && { echo "No key found with ID: $arg"; exit 1; }
    else
      key=$(sudo headscale preauthkeys list "${USER_FLAG[@]}" --output json \
        | jq -r --arg m "tag:machine:${arg}" '.[] | select((.acl_tags // [])[] == $m) | .key')
      [ -z "$key" ] && { echo "No key found with tag tag:machine:$arg"; exit 1; }
    fi
    sudo headscale preauthkeys expire "$key" "${USER_FLAG[@]}"
    echo "Revoked key (argument: $arg)"
    ;;
  show)
    [ -z "$arg" ] && usage
    sudo headscale preauthkeys list "${USER_FLAG[@]}" --output json \
      | jq -r --arg m "tag:machine:${arg}" '
        .[]
        | select((.acl_tags // [])[] == $m)
        | .key
      '
    ;;
  qr)
    [ -z "$arg" ] && usage
    if ! command -v qrencode >/dev/null 2>&1; then
      echo "ERROR: qrencode not installed. Install with: sudo apt install -y qrencode"
      exit 1
    fi
    key=$(sudo headscale preauthkeys list "${USER_FLAG[@]}" --output json \
      | jq -r --arg m "tag:machine:${arg}" '
        .[]
        | select((.acl_tags // [])[] == $m)
        | .key
      ')
    [ -z "$key" ] && { echo "No key found with tag tag:machine:$arg"; exit 1; }
    echo "QR code for $arg:"
    echo "$key" | qrencode -t ansiutf8
    ;;
  *)
    usage
    ;;
esac
