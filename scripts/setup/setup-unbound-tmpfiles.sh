#!/usr/bin/env bash
set -euo pipefail

TF=/etc/tmpfiles.d/unbound.conf
WANT='L /run/unbound.ctl 0660 root unbound - -'

# write only if missing or different
if ! sudo test -f "$TF" || ! sudo grep -Fxq "$WANT" "$TF"; then
  echo "Installing $TF"
  echo "$WANT" | sudo tee "$TF" > /dev/null
else
  echo "$TF already correct"
fi

# apply immediately
sudo systemd-tmpfiles --create "$TF"

# fix existing socket now
if [ -e /run/unbound.ctl ]; then
  sudo chown root:unbound /run/unbound.ctl || true
  sudo chmod 0660 /run/unbound.ctl || true
fi

echo "Done"
