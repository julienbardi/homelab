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

USER_ID=1
HOST="nas.bardi.ch"
PORT=8080

usage() {
  echo "Usage: $0 {new <machine>|list|revoke <machine|id>|qr <machine>|show <machine>}"
  exit 1
}

check_tls_cert() {
  echo "Checking TLS certificate for https://$HOST:$PORT ..."
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
    key=$(docker exec headscale headscale preauthkeys create \
      --user "$USER_ID" --reusable --expiration 24h \
      --tags "tag:machine:${arg}" \
      --output json | jq -r '.key // .Key')

    if [ "$key" = "null" ] || [ -z "$key" ]; then
      echo "ERROR: Failed to obtain a preauth key."
      exit 1
    fi

    echo "Key for $arg: $key"
    echo "Client command:"
    echo "  tailscale up --login-server=https://$HOST:$PORT --authkey=$key"
    echo "QR code: $0 qr $arg"
    ;;

  list)
    docker exec headscale headscale preauthkeys list --user "$USER_ID"
    ;;

  revoke)
    [ -z "$arg" ] && usage

    if [[ "$arg" =~ ^[0-9]+$ ]]; then
      # Numeric ID: look up the actual key string
      key=$(docker exec headscale headscale preauthkeys list --user "$USER_ID" --output json \
        | jq -r --arg id "$arg" '.[] | select((.id|tostring) == $id) | .key')
      [ -z "$key" ] && { echo "No key found with ID: $arg"; exit 1; }
    else
      # Lookup by tag
      key=$(docker exec headscale headscale preauthkeys list --user "$USER_ID" --output json \
        | jq -r --arg m "tag:machine:${arg}" '.[] | select((.acl_tags // [])[] == $m) | .key')
      [ -z "$key" ] && { echo "No key found with tag tag:machine:$arg"; exit 1; }
    fi

    docker exec headscale headscale preauthkeys expire "$key" --user "$USER_ID"
    echo "Revoked key (argument: $arg)"
    ;;

  show)
    [ -z "$arg" ] && usage
    docker exec headscale headscale preauthkeys list --user "$USER_ID" --output json \
      | jq -r --arg m "tag:machine:${arg}" '
        .[]
        | select((.acl_tags // [])[] == $m)
        | .key
      '
    ;;

  qr)
    [ -z "$arg" ] && usage
    if ! command -v qrencode >/dev/null 2>&1; then
      echo "ERROR: qrencode not installed. Install with: sudo apt update && sudo apt install -y qrencode"
      exit 1
    fi
    key=$(docker exec headscale headscale preauthkeys list --user "$USER_ID" --output json \
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
