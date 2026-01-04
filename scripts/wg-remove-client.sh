#!/bin/sh
# wg-remove-client.sh - robust removal of a generated client and its server peer entry.
# Usage: remove-client.sh <base> <iface>
set -eu

WG_DIR="${WG_DIR:-/etc/wireguard}"
MAP_FILE="${MAP_FILE:-${WG_DIR}/client-map.csv}"
WG_BIN="${WG_BIN:-/usr/bin/wg}"
RUN_AS_ROOT="${RUN_AS_ROOT:-./bin/run-as-root}"

PLAN="${PLAN:-/volume1/homelab/wireguard/compiled/plan.tsv}"
SCRIPTS="${SCRIPTS:-$(dirname "$0")}"

err() { printf '%s\n' "$*" >&2; }

if [ $# -lt 2 ]; then
		err "Usage: $(basename "$0") <base> <iface>"
		exit 2
fi

BASE="$1"
IFACE="$2"

# --------------------------------------------------------------------
# Validate iface against intent (authoritative)
# --------------------------------------------------------------------
if ! "$SCRIPTS/wg-plan-ifaces.sh" "$PLAN" | grep -qx "$IFACE"; then
		err "iface '$IFACE' is not present in intent (plan.tsv)"
		exit 2
fi

# validate BASE+IFACE pair exists in intent
if ! awk -F'\t' -v b="$BASE" -v i="$IFACE" '
		/^#/ || /^[[:space:]]*$/ { next }
		$1=="base" && $2=="iface" && $3=="hostid" { next }
		$1==b && $2==i { found=1 }
		END { exit(found?0:1) }
' "$PLAN"; then
		err "no client '$BASE' on iface '$IFACE' in intent"
		exit 2
fi

CONFNAME="${BASE}-${IFACE}"
KEY_FILE="${WG_DIR}/${CONFNAME}.key"
PUB_FILE="${WG_DIR}/${CONFNAME}.pub"
CONF_FILE="${WG_DIR}/${CONFNAME}.conf"
SERVER_CONF="${WG_DIR}/${IFACE}.conf"

# --------------------------------------------------------------------
# 1) Backup server conf (best-effort)
# --------------------------------------------------------------------
if [ -f "$SERVER_CONF" ]; then
		BACKUP_DIR="/var/backups"
		mkdir -p "$BACKUP_DIR"
		TSTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
		cp -a "$SERVER_CONF" "${BACKUP_DIR}/${IFACE}.conf.before-remove.${TSTAMP}.bak" 2>/dev/null || true
		printf 'ℹ️ backed up %s to %s\n' \
				"$SERVER_CONF" "${BACKUP_DIR}/${IFACE}.conf.before-remove.${TSTAMP}.bak"
fi

# --------------------------------------------------------------------
# 2) Read pubkey (if present)
# --------------------------------------------------------------------
GEN_PUB=""
if [ -f "$PUB_FILE" ]; then
		GEN_PUB="$(cat "$PUB_FILE" 2>/dev/null || true)"
fi

# --------------------------------------------------------------------
# 3) Remove peer from running kernel (if present)
# --------------------------------------------------------------------
if [ -n "$GEN_PUB" ]; then
		if [ -x "$RUN_AS_ROOT" ]; then
				"$RUN_AS_ROOT" sh -c "$WG_BIN set $IFACE peer '$GEN_PUB' remove" 2>/dev/null || true
		else
				$WG_BIN set "$IFACE" peer "$GEN_PUB" remove 2>/dev/null || true
		fi
		printf '➖ removed peer from kernel (if present)\n'
fi

# --------------------------------------------------------------------
# 4) Remove peer block from server conf (shell-buffered, robust)
# --------------------------------------------------------------------
if [ -f "$SERVER_CONF" ]; then
		TMP="$(mktemp "/tmp/${IFACE}.conf.remove.XXXXXX")"
		in_peer=0
		skip=0
		buf=""

		while IFS= read -r line || [ -n "$line" ]; do
				case "$line" in
						'[Peer]'*)
								if [ "$in_peer" -eq 1 ] && [ "$skip" -eq 0 ]; then
										printf '%s' "$buf" >> "$TMP"
								fi
								in_peer=1
								skip=0
								buf="$line\n"
								continue
								;;
				esac

				if [ "$in_peer" -eq 1 ]; then
						buf="$buf$line\n"
						case "$line" in
								*"$CONFNAME"*|*"$GEN_PUB"*) skip=1 ;;
						esac
						if [ -z "$line" ]; then
								if [ "$skip" -eq 0 ]; then
										printf '%s' "$buf" >> "$TMP"
								fi
								in_peer=0
								buf=""
								skip=0
						fi
						continue
				fi

				printf '%s\n' "$line" >> "$TMP"
		done < "$SERVER_CONF"

		if [ "$in_peer" -eq 1 ] && [ "$skip" -eq 0 ]; then
				printf '%s' "$buf" >> "$TMP"
		fi

		if [ -s "$TMP" ]; then
				if [ -x "$RUN_AS_ROOT" ]; then
						"$RUN_AS_ROOT" sh -c "mv '$TMP' '$SERVER_CONF' && chmod 600 '$SERVER_CONF'"
				else
						mv "$TMP" "$SERVER_CONF" && chmod 600 "$SERVER_CONF"
				fi
				printf '➖ removed peer block from %s\n' "$SERVER_CONF"
		else
				rm -f "$TMP" 2>/dev/null || true
				printf 'ℹ️ no matching peer block found in %s\n' "$SERVER_CONF"
		fi
fi

# --------------------------------------------------------------------
# 5) Remove client files (idempotent)
# --------------------------------------------------------------------
rm -f "$CONF_FILE" "$KEY_FILE" "$PUB_FILE" 2>/dev/null || true
printf '➖ removed client files: %s %s %s\n' "$CONF_FILE" "$KEY_FILE" "$PUB_FILE"

# --------------------------------------------------------------------
# 6) Remove client entry from client-map.csv (if present)
# --------------------------------------------------------------------
if [ -f "$MAP_FILE" ]; then
		TMPMAP="$(mktemp "/tmp/client-map.rm.XXXXXX")"
		awk -F, -v base="$BASE" -v iface="$IFACE" \
				'BEGIN{OFS=","} !($1==base && $2==iface){print $0}' \
				"$MAP_FILE" > "$TMPMAP" || true

		if [ -s "$TMPMAP" ]; then
				if [ -x "$RUN_AS_ROOT" ]; then
						"$RUN_AS_ROOT" sh -c "mv '$TMPMAP' '$MAP_FILE' && chmod 600 '$MAP_FILE'"
				else
						mv "$TMPMAP" "$MAP_FILE" && chmod 600 "$MAP_FILE"
				fi
				printf '➖ removed %s,%s from %s\n' "$BASE" "$IFACE" "$MAP_FILE"
		else
				rm -f "$TMPMAP" 2>/dev/null || true
				printf 'ℹ️ no entry %s,%s in %s\n' "$BASE" "$IFACE" "$MAP_FILE"
		fi
fi

printf '✅ removal complete for %s on %s\n' "$BASE" "$IFACE"
exit 0
