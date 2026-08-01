#!/usr/bin/env bash
set -euo pipefail

# Resolve directory of this script (works in /usr/local/bin, works anywhere)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load homelab operator environment from same directory
source "$SCRIPT_DIR/common.sh"

RUNTIME_SNAP_BEFORE="$1"
RUNTIME_SNAP_AFTER="$2"

echo "🔍 Checking runtime network state"

difffile="$($(run_as_root) sh -c 'mktemp -p /run homelab.XXXXXX' 2>/dev/null || mktemp -p /run homelab.XXXXXX)"

case "$difffile" in
  /run/*)
    $(run_as_root) sh -c ': > "$1" && chmod 644 "$1"' _ "$difffile"
    trap '$(run_as_root) rm -f "$difffile" >/dev/null 2>&1 || true' EXIT INT TERM
    ;;
  *)
    : >"$difffile"; chmod 644 "$difffile"
    trap 'rm -f "$difffile" >/dev/null 2>&1 || true' EXIT INT TERM
    ;;
esac

# Compare snapshots
for f in wg.dump ip.addr route.v4 route.v6; do
  before="$RUNTIME_SNAP_BEFORE/$f"
  after="$RUNTIME_SNAP_AFTER/$f"
  if ! diff -u "$before" "$after" >/dev/null 2>&1; then
    case "$f" in
      wg.dump)  echo "WG_CHANGED=1"   | $(run_as_root) tee -a "$difffile" >/dev/null ;;
      ip.addr)  echo "IP_CHANGED=1"   | $(run_as_root) tee -a "$difffile" >/dev/null ;;
      route.v4) echo "ROUTE4_CHANGED=1" | $(run_as_root) tee -a "$difffile" >/dev/null ;;
      route.v6) echo "ROUTE6_CHANGED=1" | $(run_as_root) tee -a "$difffile" >/dev/null ;;
    esac
  fi
done

# If no drift ➡️ done
if ! $(run_as_root) sh -c '[ -s "$1" ]' _ "$difffile"; then
  echo "♻️  Runtime network state already converged"
  exit 0
fi

echo "⚠️  Runtime network drift detected"
$(run_as_root) sh -c 'sed "s/^/   - /" "$1"' _ "$difffile"

# Drift cause classification
echo "🔍 Classifying drift cause..."
cause="unknown"

if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -u nftables 2>/dev/null | grep -q "Reloading"'; then
  cause="firewall_reload"
fi

if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -u systemd-sysctl 2>/dev/null | grep -q "Finished Apply Kernel Variables"'; then
  cause="sysctl_reload"
fi

if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -u router-prefix-watchdog 2>/dev/null | grep -q "prefix check"'; then
  cause="router_prefix_watchdog"
fi

if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -k 2>/dev/null | grep -Eq "link is (up|down)"'; then
  cause="interface_bounce"
fi

if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -u headscale 2>/dev/null | grep -q "Started Headscale coordination server"'; then
  cause="headscale_restart"
fi

echo "   ➡️ Cause: $cause"

# Transient drift suppression
continue_flag=0

IP_CHANGED="$(grep -q '^IP_CHANGED=1' "$difffile" && echo 1 || echo 0)"
ROUTE4_CHANGED="$(grep -q '^ROUTE4_CHANGED=1' "$difffile" && echo 1 || echo 0)"
ROUTE6_CHANGED="$(grep -q '^ROUTE6_CHANGED=1' "$difffile" && echo 1 || echo 0)"

if [ "$IP_CHANGED" = "1" ]; then
  final_ip="$(awk '/inet / {print $2}' $RUNTIME_SNAP_AFTER/ip.addr | cut -d/ -f1)"
  desired_ip="$(awk '/inet / {print $2}' $RUNTIME_SNAP_BEFORE/ip.addr | cut -d/ -f1)"
  if [ "$final_ip" = "$desired_ip" ]; then
    echo "♻️  Suppressed: transient IP drift (final state correct)"
    continue_flag=1
  fi
fi

if [ "$ROUTE4_CHANGED" = "1" ]; then
  final_r4="$(awk '/default/ {print $3}' $RUNTIME_SNAP_AFTER/route.v4)"
  desired_r4="$(awk '/default/ {print $3}' $RUNTIME_SNAP_BEFORE/route.v4)"
  if [ "$final_r4" = "$desired_r4" ]; then
    echo "♻️  Suppressed: transient IPv4 route drift (final state correct)"
    continue_flag=1
  fi
fi

if [ "$ROUTE6_CHANGED" = "1" ]; then
  final_r6="$(awk '/default/ {print $3}' $RUNTIME_SNAP_AFTER/route.v6)"
  desired_r6="$(awk '/default/ {print $3}' $RUNTIME_SNAP_BEFORE/route.v6)"
  if [ "$final_r6" = "$desired_r6" ]; then
    echo "♻️  Suppressed: transient IPv6 route drift (final state correct)"
    continue_flag=1
  fi
fi

if grep -q '^WG_CHANGED=1' "$difffile"; then
  tmp_before="$(mktemp)"
  tmp_after="$(mktemp)"
  awk '{ if (NF >= 5) { print $1, $2, $3, $4, $5 } else { print $0 } }' \
    "$RUNTIME_SNAP_BEFORE/wg.dump" > "$tmp_before"
  awk '{ if (NF >= 5) { print $1, $2, $3, $4, $5 } else { print $0 } }' \
    "$RUNTIME_SNAP_AFTER/wg.dump" > "$tmp_after"
  if diff -u "$tmp_before" "$tmp_after" >/dev/null 2>&1; then
    echo "♻️  Suppressed: transient WireGuard drift (final state correct)"
    continue_flag=1
  fi
  rm -f "$tmp_before" "$tmp_after" >/dev/null 2>&1 || true
fi

if [ "$continue_flag" = "1" ]; then
  echo "♻️  Runtime network state already converged (after suppression)"
  exit 0
fi

if [ "${FORCE:-0}" != "1" ]; then
  echo ""
  echo "➡️ Re-run with:"
  echo "   sudo FORCE=1 make all"
  exit 1
fi

echo "♻️  Runtime network state converged (FORCE=1 override)"
