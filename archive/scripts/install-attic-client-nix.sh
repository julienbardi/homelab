#!/bin/sh
set -eu

# Install Attic client via Nix and expose it through a root-owned wrapper.
# This script must be run as an unprivileged user; it escalates only to
# install the wrapper.

ATTIC_PROFILE="github:zhaofengli/attic"
WRAPPER_SRC="$(cd "$(dirname "$0")/.." && pwd)/bin/attic"
WRAPPER_DST="/usr/local/bin/attic"

echo "[attic-client] verifying execution context"
if [ "$(id -u)" -eq 0 ]; then
	echo "[attic-client] ERROR: do not run this script as root" >&2
	exit 1
fi

echo "[attic-client] checking for nix"
if ! command -v nix >/dev/null 2>&1; then
	echo "[attic-client] ERROR: nix not found in PATH" >&2
	echo "[attic-client] install Nix first, then re-run" >&2
	exit 1
fi

echo "[attic-client] verifying wrapper source"
if [ ! -x "$WRAPPER_SRC" ]; then
	echo "[attic-client] ERROR: wrapper not found or not executable:" >&2
	echo "  $WRAPPER_SRC" >&2
	exit 1
fi

echo "[attic-client] installing Attic client into user Nix profile"
nix profile add "$ATTIC_PROFILE"

echo "[attic-client] verifying client binary"
if ! command -v attic >/dev/null 2>&1; then
	echo "[attic-client] ERROR: attic not found in PATH after Nix install" >&2
	exit 1
fi

echo "[attic-client] installing root-owned wrapper to $WRAPPER_DST"
if ! command -v sudo >/dev/null 2>&1; then
	echo "[attic-client] ERROR: sudo not available to install wrapper" >&2
	exit 1
fi

echo "[attic-client] normalizing wrapper line endings"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

tr -d '\r' < "$WRAPPER_SRC" > "$tmp"
sudo install -m 0755 "$tmp" "$WRAPPER_DST"

echo "[attic-client] done"
echo "[attic-client] attic client available via $WRAPPER_DST"
