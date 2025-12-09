#!/usr/bin/env bash
set -euo pipefail

# wg-restart-all.sh
# Idempotent restart of wg0..wg7 with fallback for failing PostUp hooks.
# Usage: sudo wg-restart-all.sh [--no-peers] [--ifaces wg0,wg1] [--tries N]

WG_DIR="/etc/wireguard"
WG_QUICK="$(command -v wg-quick || true)"
WG_BIN="$(command -v wg || true)"
MAKE_CMD="${MAKE_CMD:-make}"
DEFAULT_IFACES="wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7"
TRIES=2
NO_PEERS=0
IFACES=""
LOGDIR_BASE="/var/log/wg-restart"
SLEEP_BASE=1

die(){ echo "ERROR: $*" >&2; exit 2; }
info(){ echo "$*"; }

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
	--no-peers) NO_PEERS=1; shift ;;
	--ifaces) IFACES="$2"; shift 2 ;;
	--tries) TRIES="$2"; shift 2 ;;
	-h|--help) echo "Usage: $0 [--no-peers] [--ifaces wg0,wg1] [--tries N]"; exit 0 ;;
	*) die "Unknown arg: $1" ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  die "must be run as root (use sudo)"
fi

LOGDIR="${LOGDIR_BASE}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR" || die "cannot create $LOGDIR"
info "Logs: $LOGDIR"

if [ -n "$IFACES" ]; then
  IFS=',' read -r -a IFACE_ARR <<< "$IFACES"
else
  IFS=' ' read -r -a IFACE_ARR <<< "$DEFAULT_IFACES"
fi

any_up=0
failures=()

for dev in "${IFACE_ARR[@]}"; do
  conf="$WG_DIR/${dev}.conf"
  info "----"
  info "Processing $dev (conf: $conf)"

  if [ ! -f "$conf" ]; then
	info "⏭ skipping $dev: config not found"
	continue
  fi

  # 1) syntax check
  if ! $WG_QUICK strip "$conf" >/dev/null 2>&1; then
	info "✗ parse FAILED for $conf (wg-quick strip). Saving copy to logs."
	cp -a "$conf" "$LOGDIR/${dev}-conf-bad.conf" || true
	failures+=("$dev:parse")
	continue
  fi

  # 2) key check
  keyfile="$WG_DIR/${dev}.key"
  if [ ! -f "$keyfile" ]; then
	info "✗ missing private key: $keyfile"
	failures+=("$dev:key-missing")
	continue
  fi
  chmod 600 "$keyfile" || true

  # 3) ensure clean state
  $WG_QUICK down "$dev" >/dev/null 2>&1 || true
  ip link delete dev "$dev" >/dev/null 2>&1 || true

  # 4) try up with retries
  up_ok=0
  attempt=1
  while [ $attempt -le "$TRIES" ]; do
	info "⏫ Attempt $attempt/$TRIES: wg-quick up $dev"
	if $WG_QUICK up "$dev" > "$LOGDIR/${dev}-up-${attempt}.out" 2>&1; then
	  info "✅ $dev up (attempt $attempt)"
	  up_ok=1
	  break
	else
	  info "⚠ wg-quick up $dev failed (see $LOGDIR/${dev}-up-${attempt}.out)"
	  journalctl -u "wg-quick@${dev}" -n 80 --no-pager > "$LOGDIR/${dev}-journal-${attempt}.log" 2>/dev/null || true
	  sleep_time=$(( SLEEP_BASE * (2 ** (attempt - 1)) ))
	  info "⤴ sleeping ${sleep_time}s before retry"
	  sleep "$sleep_time"
	fi
	attempt=$((attempt + 1))
  done

  # 5) fallback: try up with hooks disabled (comment PostUp/PreDown)
  if [ $up_ok -ne 1 ]; then
	info "⤴ Fallback: trying to bring $dev up with hooks disabled"
	tmpconf="$(mktemp /tmp/${dev}.conf.XXXX)"
	sed -E 's/^[[:space:]]*(PostUp|PreDown)[[:space:]]*=/# &/I' "$conf" > "$tmpconf"
	chmod 600 "$tmpconf"
	if $WG_QUICK up "$tmpconf" > "$LOGDIR/${dev}-up-fallback.out" 2>&1; then
	  info "⚠️  $dev up with hooks disabled — PostUp/PreDown likely failing. See $LOGDIR/${dev}-up-fallback.out"
	  up_ok=1
	  echo "FALLBACK: hooks disabled" > "$LOGDIR/${dev}-fallback-note.txt"
	else
	  info "✗ fallback also failed for $dev (see $LOGDIR/${dev}-up-fallback.out)"
	  journalctl -u "wg-quick@${dev}" -n 120 --no-pager > "$LOGDIR/${dev}-journal-fallback.log" 2>/dev/null || true
	fi
	rm -f "$tmpconf" || true
  fi

  if [ $up_ok -eq 1 ]; then
	any_up=1
	$WG_BIN show "$dev" > "$LOGDIR/${dev}-wg-show.out" 2>/dev/null || true
	ip -6 addr show dev "$dev" > "$LOGDIR/${dev}-ip6-addr.out" 2>/dev/null || true
	ip -6 route show dev "$dev" > "$LOGDIR/${dev}-ip6-route.out" 2>/dev/null || true
  else
	failures+=("$dev:up-failed")
  fi
done

# Optionally program peers
if [ "$NO_PEERS" -eq 0 ]; then
  info "🔁 Running peer programming: ${MAKE_CMD} wg-add-peers"
  if $MAKE_CMD wg-add-peers > "$LOGDIR/wg-add-peers.out" 2>&1; then
	info "✅ wg-add-peers completed"
  else
	info "⚠ wg-add-peers failed (see $LOGDIR/wg-add-peers.out)"
	failures+=("wg-add-peers")
  fi
else
  info "⏭ Skipping wg-add-peers (user requested --no-peers)"
fi

# Final summary
echo "==== SUMMARY ===="
if [ ${#failures[@]} -eq 0 ] && [ $any_up -eq 1 ]; then
  echo "All requested interfaces processed; peers applied (if requested)."
  echo "Logs: $LOGDIR"
  exit 0
fi

echo "Some items failed or were skipped:"
[ ${#failures[@]} -gt 0 ] && echo " - Failures: ${failures[*]}"
[ $any_up -eq 0 ] && echo " - No interfaces were brought up successfully."
echo "Inspect logs in: $LOGDIR"
exit 1
