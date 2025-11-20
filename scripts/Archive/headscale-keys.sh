#!/bin/bash
set -euo pipefail
source "/home/julie/homelab/scripts/config/homelab.env"

usage() {
  echo "Usage: $0 {list|new <name>|revoke <id|name>|show <name>|qr <name>}"
  exit 1
}

list_keys() {
  headscale preauthkeys list --output json | jq .
}

new_key() {
  NAME=$1
  headscale preauthkeys create \
    --reusable \
    --expiration 24h \
    --output json \
    --tags "tag:${NAME}" | tee "${CLIENTS_DIR}/headscale-${NAME}.json"
}

revoke_key() {
  ARG=$1
  if [[ "$ARG" =~ ^[0-9]+$ ]]; then
    headscale preauthkeys expire --id "$ARG"
  else
    ID=$(headscale preauthkeys list --output json | jq -r ".[] | select(.ephemeral==false and .tags[]?==\"tag:${ARG}\") | .id")
    if [[ -n "$ID" ]]; then
      headscale preauthkeys expire --id "$ID"
    else
      echo "❌ No key found for $ARG"
      exit 1
    fi
  fi
}

show_key() {
  NAME=$1
  FILE="${CLIENTS_DIR}/headscale-${NAME}.json"
  if [[ -f "$FILE" ]]; then
    jq . "$FILE"
  else
    echo "❌ No key file found for $NAME"
    exit 1
  fi
}

qr_key() {
  NAME=$1
  FILE="${CLIENTS_DIR}/headscale-${NAME}.json"
  if [[ -f "$FILE" ]]; then
    KEY=$(jq -r .key "$FILE")
    echo -n "$KEY" | qrencode -t ansiutf8
  else
    echo "❌ No key file found for $NAME"
    exit 1
  fi
}

case "${1:-}" in
  list) list_keys ;;
  new) [[ $# -eq 2 ]] || usage; new_key "$2" ;;
  revoke) [[ $# -eq 2 ]] || usage; revoke_key "$2" ;;
  show) [[ $# -eq 2 ]] || usage; show_key "$2" ;;
  qr) [[ $# -eq 2 ]] || usage; qr_key "$2" ;;
  *) usage ;;
esac
