#!/bin/sh

# Load KEYID from private config file
KEYID="$(cat "$HOME/config/homelab/gpg-keyid")"

: "${KEYID:?missing KEYID}"

gpg --batch --yes --pinentry-mode loopback \
    --local-user "$KEYID" \
    --detach-sign "$1"
