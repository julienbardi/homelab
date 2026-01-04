#!/usr/bin/env bash
set -euo pipefail
# shellcheck shell=bash

# wg-runtime-recover.sh
# Plan-driven runtime restart + diagnostics (no config mutation, no peer programming).
#
# Usage:
#   sudo WG_ROOT=/volume1/homelab/wireguard ./scripts/wg-runtime-recover.sh \
#        [--ifaces wg0,wg1] [--tries N] [--no-down] [--dry-run]
#
# Exit:
#   0 if all requested interfaces that had configs were brought up
#   1 otherwise (details in summary + logs)

WG_ROOT="${WG_ROOT:-}"
WG_DIR="${WG_DIR:-/etc/wireguard}"
PLAN_REL="compiled/plan.tsv"
PLAN="${PLAN:-${WG_ROOT:+$WG_ROOT/}$PLAN_REL}"

WG_QUICK="$(command -v wg-quick || true)"
WG_BIN="$(command -v wg || true)"
IP_BIN="$(command -v ip || true)"
JOURNALCTL_BIN="$(command -v journalctl || true)"

TRIES=2
NO_DOWN=0
DRY_RUN=0
IFACES_CSV=""
LOGDIR_BASE="/var/log/wg-runtime-recover"
SLEEP_BASE=1

die(){ echo "ERROR: $*" >&2; exit 2; }
info(){ echo "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
	echo "+ $*"
	return 0
  fi
  "$@"
}

# args
while [ $# -gt 0 ]; do
  case "$1" in
	--ifaces) IFACES_CSV="${2:-}"; shift 2 ;;
	--tries) TRIES="${2:-}"; shift 2 ;;
	--no-down) NO_DOWN=1; shift ;;
	--dry-run) DRY_RUN=1; shift ;;
	-h|--help)
	  cat <<EOF
Usage: sudo WG_ROOT=... $0 [--ifaces wg0,wg1] [--tries N] [--no-down] [--dry-run]

Defaults:
  --ifaces: derived from intent plan.tsv
  --tries:  2
EOF
	  exit 0
	  ;;
	*) die "Unknown arg: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "must be run as root (use sudo)"
need_cmd wg-quick
need_cmd wg
need_cmd ip

if [ -z "$WG_ROOT" ]; then
  die "WG_ROOT must be set (used to locate compiled/plan.tsv)"
fi
[ -f "$PLAN" ] || die "missing plan file: $PLAN"

# logdir
LOGDIR="${LOGDIR_BASE}-$(date +%Y%m%d-%H%M%S)"
run mkdir -p "$LOGDIR" || die "cannot create $LOGDIR"
info "Logs: $LOGDIR"

# derive interfaces from intent unless overridden
if [ -n "$IFACES_CSV" ]; then
  IFS=',' read -r -a IFACE_ARR <<<"$IFACES_CSV"
else
	mapfile -t IFACE_ARR < <(
		awk -F'\t' '
		/^#/ { next }
		/^[[:space:]]*$/ { next }
		$1=="base" && $2=="iface" { print $3 }
		' "$PLAN" | sort -u
	)
fi

[ "${#IFACE_ARR[@]}" -gt 0 ] || die "no interfaces selected (empty plan?)"

any_up=0
failures=()

for dev in "${IFACE_ARR[@]}"; do
  conf="$WG_DIR/${dev}.conf"
  keyfile="$WG_DIR/${dev}.key"

  info "----"
  info "Processing $dev"
  info "  conf: $conf"

  if [ ! -f "$conf" ]; then
	info "⏭ skipping $dev: not deployed (missing $conf)"
	failures+=("$dev:missing-conf")
	continue
  fi

  # parse check (strip validates wg-quick syntax)
  if ! run "$WG_QUICK" strip "$conf" >/dev/null 2>&1; then
	info "✗ parse FAILED for $conf (wg-quick strip). Saving copy."
	run cp -a "$conf" "$LOGDIR/${dev}-conf-bad.conf" || true
	failures+=("$dev:parse")
	continue
  fi

  if [ ! -f "$keyfile" ]; then
	info "✗ missing private key: $keyfile"
	failures+=("$dev:key-missing")
	continue
  fi
  run chmod 600 "$keyfile" || true

  # clean state unless user requested otherwise
  if [ "$NO_DOWN" -eq 0 ]; then
	run "$WG_QUICK" down "$dev" >/dev/null 2>&1 || true
	run "$IP_BIN" link delete dev "$dev" >/dev/null 2>&1 || true
  fi

  up_ok=0
  attempt=1
  while [ "$attempt" -le "$TRIES" ]; do
	info "⏫ Attempt $attempt/$TRIES: wg-quick up $dev"
	if run "$WG_QUICK" up "$dev" >"$LOGDIR/${dev}-up-${attempt}.out" 2>&1; then
	  info "✅ $dev up (attempt $attempt)"
	  up_ok=1
	  break
	fi

	info "⚠ wg-quick up $dev failed (see $LOGDIR/${dev}-up-${attempt}.out)"

	# capture service journal if available (best-effort)
	if [ -n "$JOURNALCTL_BIN" ]; then
	  run "$JOURNALCTL_BIN" -u "wg-quick@${dev}" -n 120 --no-pager \
		>"$LOGDIR/${dev}-journal-${attempt}.log" 2>/dev/null || true
	fi

	sleep_time=$(( SLEEP_BASE * (2 ** (attempt - 1)) ))
	info "⤴ sleeping ${sleep_time}s before retry"
	run sleep "$sleep_time"
	attempt=$((attempt + 1))
  done

  if [ "$up_ok" -eq 1 ]; then
	any_up=1
	run "$WG_BIN" show "$dev" >"$LOGDIR/${dev}-wg-show.out" 2>/dev/null || true
	run "$IP_BIN" -brief link show "$dev" >"$LOGDIR/${dev}-ip-link.out" 2>/dev/null || true
	run "$IP_BIN" -6 addr show dev "$dev" >"$LOGDIR/${dev}-ip6-addr.out" 2>/dev/null || true
	run "$IP_BIN" -6 route show dev "$dev" >"$LOGDIR/${dev}-ip6-route.out" 2>/dev/null || true
  else
	# loud diagnostics hint for hook failures without mutating config
	if grep -qiE 'PostUp|PreDown' "$conf"; then
	  {
		echo "NOTE: $conf contains PostUp/PreDown."
		echo "If up fails, suspect hook commands; see ${dev}-up-*.out and journal logs."
	  } >"$LOGDIR/${dev}-hook-hint.txt"
	fi
	failures+=("$dev:up-failed")
  fi
done

echo "==== SUMMARY ===="
echo "Selected ifaces: ${IFACE_ARR[*]}"
echo "Logs: $LOGDIR"

if [ "${#failures[@]}" -eq 0 ] && [ "$any_up" -eq 1 ]; then
  echo "OK: all selected interfaces that were deployed came up."
  exit 0
fi

echo "NOT OK:"
[ "${#failures[@]}" -gt 0 ] && echo " - Failures/skips: ${failures[*]}"
[ "$any_up" -eq 0 ] && echo " - No interfaces were brought up successfully."
exit 1
