#!/usr/bin/env bash
# scripts/setup/setup-unbound-tmpfiles.sh
set -euo pipefail

# Path to the deployed tmpfiles file and the repo source
TF=/etc/tmpfiles.d/unbound.conf
REPO_TF=config/tmpfiles/unbound.conf

WANT='L /run/unbound.ctl 0660 root unbound - -'

# Ensure repo template exists (fail early if missing)
if [ ! -f "${REPO_TF}" ]; then
  echo "ERROR: repo tmpfiles template ${REPO_TF} not found" >&2
  exit 1
fi

# Install tmpfiles entry only if missing or different
if [ ! -f "$TF" ] || ! grep -Fxq "$WANT" "$TF"; then
  echo "Installing $TF"
  install -d /etc/tmpfiles.d
  install -m 0644 "${REPO_TF}" "$TF"
else
  echo "$TF already correct"
fi

# Apply tmpfiles immediately so socket is created/owned correctly now
systemd-tmpfiles --create "$TF" || true

# Fix existing socket ownership/permissions now (if present)
if [ -e /run/unbound.ctl ]; then
  chown root:unbound /run/unbound.ctl || true
  chmod 0660 /run/unbound.ctl || true
fi

echo "Done"
