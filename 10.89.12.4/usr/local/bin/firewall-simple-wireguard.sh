#!/usr/bin/env bash
# /usr/local/bin/firewall-simple-wireguard.sh
# Minimal WireGuard FORWARD + POSTROUTING manager with a lightweight first-apply snapshot
#
# to deploy use 
#     sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/firewall-simple-wireguard.sh /usr/local/bin/firewall-simple-wireguard.sh
#     sudo chown root:root /usr/local/bin/firewall-simple-wireguard.sh
#     sudo chmod 700 /usr/local/bin/firewall-simple-wireguard.sh
#
#     Verify current nat POSTROUTING state (confirm cleanup):
#      sudo /usr/sbin/iptables-legacy -t nat -L POSTROUTING --line-numbers -n -v
#      sudo /usr/sbin/ip6tables-legacy -t nat -L POSTROUTING --line-numbers -n -v
# Prerequisites:
#
# Usage:
#   sudo firewall-simple-wireguard.sh               # dry-run (default): show planned ADD/DEL rules
#   sudo firewall-simple-wireguard.sh apply         # apply ADD rules; will snapshot on first apply then keep snapshot for emergency restore
#   sudo firewall-simple-wireguard.sh remove        # apply DEL rules (uses same snapshot behavior)
#   sudo firewall-simple-wireguard.sh inspect       # show current matching rules for wg interfaces
#   sudo firewall-simple-wireguard.sh restore-last  # emergency: restore last saved snapshot
#
# Short notes:
# - Edit only ADD_RULES / DEL_RULES below if needed; keep rules minimal (FORWARD and nat POSTROUTING).
# - Do not change INPUT or default policies here to avoid locking admin access.
# - Default is dry-run; first real apply creates a snapshot (kept for emergency restore).
# - IPv6 POSTROUTING MASQUERADE requires ip6tables nat support; remove those lines if unsupported.
# - Order: add FORWARD accepts before NAT; remove NAT before FORWARD to minimize disruption.
set -euo pipefail

# --- Configuration ---
SNAPROOT="/var/tmp/fw-snapshots"
mkdir -p "$SNAPROOT"
umask 077

LOCKFILE="/var/lock/firewall-simple-wireguard.lock"
exec {LOCKFD}>"$LOCKFILE"
flock -n "$LOCKFD" || { echo "ERROR: another instance is running"; exit 2; }

# Use these exact assignments in the script (they match DXP4800+): use sudo which iptables-legacy-restore to find correct path
IPT4_CMD="/usr/sbin/iptables-legacy"
IPT6_CMD="/usr/sbin/ip6tables-legacy"
RESTORE4_CMD="/usr/sbin/iptables-legacy-restore"
RESTORE6_CMD="/usr/sbin/ip6tables-legacy-restore"
SAVE4_CMD="/usr/sbin/iptables-legacy-save"
SAVE6_CMD="/usr/sbin/ip6tables-legacy-save"

# --- Hardcoded rules (edit only here) ---
# Manage only FORWARD and POSTROUTING; do not touch INPUT or default chain policies.
ADD_RULES=(
  # wg1 (IPv4)
  "$IPT4_CMD -A FORWARD -i wg1 -j ACCEPT"
  "$IPT4_CMD -A FORWARD -o wg1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -t nat -A POSTROUTING -s 10.1.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"

  # wg2 (IPv4)
  "$IPT4_CMD -A FORWARD -i wg2 -j ACCEPT"
  "$IPT4_CMD -A FORWARD -o wg2 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -t nat -A POSTROUTING -s 10.2.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"

  # wg3 (IPv4)
  "$IPT4_CMD -A FORWARD -i wg3 -j ACCEPT"
  "$IPT4_CMD -A FORWARD -o wg3 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -t nat -A POSTROUTING -s 10.3.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"

  # wg4 (IPv4 + IPv6)
  "$IPT4_CMD -A FORWARD -i wg4 -j ACCEPT"
  "$IPT4_CMD -A FORWARD -o wg4 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -t nat -A POSTROUTING -s 10.4.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT6_CMD -A FORWARD -i wg4 -j ACCEPT"
  "$IPT6_CMD -A FORWARD -o wg4 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT6_CMD -t nat -A POSTROUTING -s fd10:4::/64 -o bridge0 -j MASQUERADE"

  # wg5 (IPv4 + IPv6)
  "$IPT4_CMD -A FORWARD -i wg5 -j ACCEPT"
  "$IPT4_CMD -A FORWARD -o wg5 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -t nat -A POSTROUTING -s 10.5.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT6_CMD -A FORWARD -i wg5 -j ACCEPT"
  "$IPT6_CMD -A FORWARD -o wg5 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT6_CMD -t nat -A POSTROUTING -s fd10:5::/64 -o bridge0 -j MASQUERADE"

  # wg6 (IPv4 + IPv6)
  "$IPT4_CMD -A FORWARD -i wg6 -j ACCEPT"
  "$IPT4_CMD -A FORWARD -o wg6 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -t nat -A POSTROUTING -s 10.6.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT6_CMD -A FORWARD -i wg6 -j ACCEPT"
  "$IPT6_CMD -A FORWARD -o wg6 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT6_CMD -t nat -A POSTROUTING -s fd10:6::/64 -o bridge0 -j MASQUERADE"

  # wg7 (IPv4 + IPv6)
  "$IPT4_CMD -A FORWARD -i wg7 -j ACCEPT"
  "$IPT4_CMD -A FORWARD -o wg7 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -t nat -A POSTROUTING -s 10.7.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT6_CMD -A FORWARD -i wg7 -j ACCEPT"
  "$IPT6_CMD -A FORWARD -o wg7 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT6_CMD -t nat -A POSTROUTING -s fd10:7::/64 -o bridge0 -j MASQUERADE"
)

DEL_RULES=(
  # wg1
  "$IPT4_CMD -t nat -D POSTROUTING -s 10.1.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT4_CMD -D FORWARD -o wg1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -D FORWARD -i wg1 -j ACCEPT"

  # wg2
  "$IPT4_CMD -t nat -D POSTROUTING -s 10.2.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT4_CMD -D FORWARD -o wg2 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -D FORWARD -i wg2 -j ACCEPT"

  # wg3
  "$IPT4_CMD -t nat -D POSTROUTING -s 10.3.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT4_CMD -D FORWARD -o wg3 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -D FORWARD -i wg3 -j ACCEPT"

  # wg4
  "$IPT6_CMD -t nat -D POSTROUTING -s fd10:4::/64 -o bridge0 -j MASQUERADE"
  "$IPT6_CMD -D FORWARD -o wg4 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT6_CMD -D FORWARD -i wg4 -j ACCEPT"
  "$IPT4_CMD -t nat -D POSTROUTING -s 10.4.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT4_CMD -D FORWARD -o wg4 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -D FORWARD -i wg4 -j ACCEPT"

  # wg5
  "$IPT6_CMD -t nat -D POSTROUTING -s fd10:5::/64 -o bridge0 -j MASQUERADE"
  "$IPT6_CMD -D FORWARD -o wg5 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT6_CMD -D FORWARD -i wg5 -j ACCEPT"
  "$IPT4_CMD -t nat -D POSTROUTING -s 10.5.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT4_CMD -D FORWARD -o wg5 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -D FORWARD -i wg5 -j ACCEPT"

  # wg6
  "$IPT6_CMD -t nat -D POSTROUTING -s fd10:6::/64 -o bridge0 -j MASQUERADE"
  "$IPT6_CMD -D FORWARD -o wg6 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT6_CMD -D FORWARD -i wg6 -j ACCEPT"
  "$IPT4_CMD -t nat -D POSTROUTING -s 10.6.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT4_CMD -D FORWARD -o wg6 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -D FORWARD -i wg6 -j ACCEPT"

  # wg7
  "$IPT6_CMD -t nat -D POSTROUTING -s fd10:7::/64 -o bridge0 -j MASQUERADE"
  "$IPT6_CMD -D FORWARD -o wg7 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT6_CMD -D FORWARD -i wg7 -j ACCEPT"
  "$IPT4_CMD -t nat -D POSTROUTING -s 10.7.0.0/24 -o bridge0 ! -d 10.89.12.0/24 -j MASQUERADE"
  "$IPT4_CMD -D FORWARD -o wg7 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
  "$IPT4_CMD -D FORWARD -i wg7 -j ACCEPT"
)

# --- Helpers: snapshot, restore, connectivity check, apply ---
snapshot_dir=""
snapshot_create_if_missing(){
  # Only create snapshot if none exists under SNAPROOT/last; keep first snapshot for emergencies.
  if [[ -L "$SNAPROOT/last" ]] && [[ -d "$(readlink -f "$SNAPROOT/last")" ]]; then
    snapshot_dir="$(readlink -f "$SNAPROOT/last")"
    return 0
  fi
  snapshot_dir="$(mktemp -d -p "$SNAPROOT" fw.snap.XXXXXX)"
  chmod 700 "$snapshot_dir"
  # iptables-save (fallback to -S)
  if command -v "$SAVE4_CMD" >/dev/null 2>&1; then
    "$SAVE4_CMD" >"$snapshot_dir/iptables.save" 2>/dev/null || iptables -S >"$snapshot_dir/iptables.save" 2>/dev/null || true
  else
    iptables -S >"$snapshot_dir/iptables.save" 2>/dev/null || true
  fi
  # ip6tables-save (fallback to -S)
  if command -v "$SAVE6_CMD" >/dev/null 2>&1; then
    "$SAVE6_CMD" >"$snapshot_dir/ip6tables.save" 2>/dev/null || ip6tables -S >"$snapshot_dir/ip6tables.save" 2>/dev/null || true
  else
    ip6tables -S >"$snapshot_dir/ip6tables.save" 2>/dev/null || true
  fi
  ln -f "$snapshot_dir" "$SNAPROOT/last" 2>/dev/null || true
}

restore_snapshot(){
  if [[ -n "${snapshot_dir:-}" ]] && [[ -d "$snapshot_dir" ]]; then
    echo "Restoring snapshot from $snapshot_dir ..."
    if [[ -f "$snapshot_dir/iptables.save" ]] && command -v "$RESTORE4_CMD" >/dev/null 2>&1; then
      "$RESTORE4_CMD" <"$snapshot_dir/iptables.save" || echo "WARN: $RESTORE4_CMD failed"
    else
      echo "WARN: $RESTORE4_CMD missing or iptables snapshot absent"
    fi
    if [[ -f "$snapshot_dir/ip6tables.save" ]] && command -v "$RESTORE6_CMD" >/dev/null 2>&1; then
      "$RESTORE6_CMD" <"$snapshot_dir/ip6tables.save" || echo "WARN: $RESTORE6_CMD failed"
    else
      echo "WARN: $RESTORE6_CMD missing or ip6tables snapshot absent"
    fi
  else
    echo "No snapshot available to restore"
  fi
}

restore_last_snapshot(){
  if [[ -L "$SNAPROOT/last" ]] && [[ -d "$(readlink -f "$SNAPROOT/last")" ]]; then
    snapshot_dir="$(readlink -f "$SNAPROOT/last")"
    restore_snapshot
  else
    echo "No last snapshot found under $SNAPROOT/last"
    exit 1
  fi
}

connectivity_check(){
  local gw ok=0
  gw="$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')"
  if [[ -n "$gw" ]]; then
    if sudo ping -c 1 -W 2 "$gw" >/dev/null 2>&1; then
      ok=0
    else
      if sudo ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        ok=0
      else
        ok=1
      fi
    fi
  else
    if sudo ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
      ok=0
    else
      ok=1
    fi
  fi

  # Informational: local sshd listen
  if ! ss -tnl 2>/dev/null | grep -E -- ':(22|2222)\b' >/dev/null 2>&1; then
    echo "Notice: local sshd not detected (ok if you are on local console)"
  fi

  return $ok
}

apply_list_with_snapshot(){
  local -n list=$1

  # Dry-run prints and exits
  if [[ "${DRY_RUN:-1}" -ne 0 ]]; then
    echo "DRY RUN: planned commands:"
    for c in "${list[@]}"; do printf "%s\n" "$c"; done
    return 0
  fi

  # Create a first snapshot if none exists (lightweight first-apply behavior)
  snapshot_create_if_missing

  # Execute commands in order
  for c in "${list[@]}"; do
    echo "+ $c"
    if ! bash -c "$c"; then
      echo "ERROR: command failed: $c"
      echo "Restoring snapshot..."
      restore_snapshot
      exit 1
    fi
  done

  # Connectivity check; restore on failure
  if ! connectivity_check; then
    echo "Connectivity checks failed; restoring snapshot..."
    restore_snapshot
    exit 1
  fi

  echo "Apply finished successfully; snapshot retained at $snapshot_dir for emergency restore."
}

inspect_current(){
  echo "IPv4 FORWARD rules referencing wg interfaces:"
  iptables -S FORWARD 2>/dev/null | grep -E -- 'wg[0-9]+' || echo "  (none)"
  echo
  echo "IPv4 POSTROUTING nat referencing 10.N.0.0/24:"
  iptables -t nat -S POSTROUTING 2>/dev/null | grep -E -- '10\.[0-9]+\.0\.0/24' || echo "  (none)"
  echo
  echo "IPv6 FORWARD rules (if any):"
  ip6tables -S FORWARD 2>/dev/null | grep -E -- 'wg[0-9]+' || echo "  (none or ip6tables missing)"
  echo
  echo "IPv6 POSTROUTING nat (if supported):"
  ip6tables -t nat -S POSTROUTING 2>/dev/null | grep -E -- 'fd10:[0-9]+' || echo "  (none or nat unsupported)"
}

# --- CLI ---
cmd="${1:-}"
if [[ -z "$cmd" ]]; then cmd="dry-run"; fi

case "$cmd" in
  dry-run)
    inspect_current
    echo
    echo "DRY RUN: ADD rules"
    for r in "${ADD_RULES[@]}"; do printf "%s\n" "$r"; done
    echo
    echo "DRY RUN: DEL rules"
    for r in "${DEL_RULES[@]}"; do printf "%s\n" "$r"; done
    ;;
  apply)
    DRY_RUN=0
    apply_list_with_snapshot ADD_RULES
    ;;
  remove)
    DRY_RUN=0
    apply_list_with_snapshot DEL_RULES
    ;;
  inspect)
    inspect_current
    ;;
  restore-last)
    restore_last_snapshot
    ;;
  *)
    echo "Usage: $0 {dry-run|apply|remove|inspect|restore-last}"
    exit 2
    ;;
esac
