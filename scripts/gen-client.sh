#!/bin/sh
# gen-client.sh
# Deterministic allocator + client generator + safe apply
# POSIX sh, no heredocs, sequential and conservative.
# Usage: gen-client.sh <base> <iface> [--force] [--conf-force]
set -eu

# ---------- Configuration ----------
WG_DIR="${WG_DIR:-/etc/wireguard}"
MAP_FILE="${MAP_FILE:-${WG_DIR}/client-map.csv}"
WG_BIN="${WG_BIN:-/usr/bin/wg}"
RUN_AS_ROOT="${RUN_AS_ROOT:-./bin/run-as-root}"
HOST_OFFSET="${HOST_OFFSET:-2}"     # first usable host (.2)
USABLE_HOSTS="${USABLE_HOSTS:-253}" # hosts .2..254
BACKUP_DIR="${BACKUP_DIR:-/var/backups}"
FORCE_REASSIGN="${FORCE_REASSIGN:-0}" # set env to 1 to allow reassignments
# ------------------------------------------------

# ---------- Sanity checks ----------
required_cmds="awk sed mktemp tar grep printf tee chmod mv mkdir rmdir date"
for c in $required_cmds; do
		command -v "$c" >/dev/null 2>&1 || { printf 'required command not found: %s\n' "$c" >&2; exit 2; }
done

command -v "$WG_BIN" >/dev/null 2>&1 || { printf 'wg binary not found at %s\n' "$WG_BIN" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'python3 required for SHA256 allocator\n' >&2; exit 2; }

umask 077

# ---------- Helpers ----------
TMPFILES=""
LOCKDIRS=""

run_root() {
		cmd="$1"
		if [ -x "$RUN_AS_ROOT" ]; then
				"$RUN_AS_ROOT" sh -c "$cmd"
		else
				sh -c "$cmd"
		fi
}

err() { printf '%s\n' "$*" >&2; }

acquire_lock() {
		lockdir="$1"
		try=0
		while ! mkdir "$lockdir" 2>/dev/null; do
				try=$((try + 1))
				if [ "$try" -gt 60 ]; then
						err "failed to acquire lock $lockdir"
						return 1
				fi
				sleep 0.1
		done
		LOCKDIRS="${LOCKDIRS} ${lockdir}"
		return 0
}

release_lock() {
		lockdir="$1"
		if [ -d "$lockdir" ]; then
				rmdir "$lockdir" 2>/dev/null || true
		fi
		# best-effort remove from LOCKDIRS
		LOCKDIRS="$(printf '%s' "$LOCKDIRS" | sed "s# $lockdir##g" | sed "s#^$lockdir##g")"
}

# alloc_index <name> <usable>
alloc_index() {
		name="$1"
		usable="$2"
		python3 -c 'import sys,hashlib; print(int(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest(),16) % int(sys.argv[2]))' "$name" "$usable"
}

read_map_lines() {
		mapfile="$1"
		if [ ! -f "$mapfile" ]; then
				return 0
		fi
		awk -F, 'BEGIN{OFS=","} /^[[:space:]]*#/ {next} /^[[:space:]]*$/ {next} {print $1,$2,$3,$4}' "$mapfile"
}

basename_from_conf() {
		f="$1"
		b="$(basename "$f")"
		printf '%s' "$b" | sed -n 's/-wg[0-9]\+\.conf$//p'
}

atomic_move_as_root() {
		src="$1"
		dst="$2"
		# escape single quotes in paths for safe sh -c usage
		esc() { printf "%s" "$1" | sed "s/'/'\\\\''/g"; }
		run_root "mv '$(esc "$src")' '$(esc "$dst")' && chmod 600 '$(esc "$dst")'"
}

# shellcheck disable=SC2317
cleanup() {
		# remove temp files safely
		for t in $TMPFILES; do
				[ -n "$t" ] || continue
				rm -f -- "$t" 2>/dev/null || true
		done
		# release locks
		for l in $LOCKDIRS; do
				[ -n "$l" ] || continue
				release_lock "$l"
		done
}
trap cleanup EXIT INT TERM

# ---------- Ensure WG_DIR exists ----------
if [ ! -d "$WG_DIR" ]; then
		run_root "install -d -m 0700 '$WG_DIR'"
fi

# ---------- Input parsing ----------
if [ $# -lt 2 ]; then
		err "Usage: $(basename "$0") <base> <iface> [--force] [--conf-force]"
		exit 2
fi

BASE="$1"; IFACE="$2"; shift 2
FORCE=0; CONF_FORCE=0
while [ $# -gt 0 ]; do
		case "$1" in
				--force|-f) FORCE=1; shift ;;
				--conf-force) CONF_FORCE=1; shift ;;
				*) shift ;;
		esac
done

case "$IFACE" in
		wg[0-9]* ) ;;
		*) err "iface must be named like wgN (e.g., wg0)"; exit 2 ;;
esac
if [ -z "$BASE" ]; then
		err "base name must be non-empty"
		exit 2
fi

CONFNAME="${BASE}-${IFACE}"
: "$CONFNAME"
SERVER_CONF="${WG_DIR}/${IFACE}.conf"

# ---------- Build base lists ----------
existing_bases=""
# safe glob loop (handles spaces in filenames)
for f in "$WG_DIR"/*-"$IFACE".conf; do
		[ -e "$f" ] || continue
		b=$(basename_from_conf "$f")
		[ -n "$b" ] && existing_bases="${existing_bases}
${b}"
done

map_bases=""
if [ -f "$MAP_FILE" ]; then
		map_tmp="$(mktemp "/tmp/client-map.map.XXXXXX")"; TMPFILES="$TMPFILES $map_tmp"
		read_map_lines "$MAP_FILE" > "$map_tmp"
		while IFS=, read -r mbase miface m4 m6; do
				[ "$miface" = "$IFACE" ] || continue
				[ -n "$mbase" ] && map_bases="${map_bases}
${mbase}"
				: "$m6"  # mark m6 as used to silence shellcheck unused-var
		done < "$map_tmp"
fi

all_bases="$(printf '%s\n%s\n%s\n' "$existing_bases" "$map_bases" "$BASE" | sed '/^[[:space:]]*$/d' | sort -u)"

# ---------- Per-interface network base ----------
iface_index="$(printf '%s' "$IFACE" | sed -n 's/^wg\([0-9]\+\)$/\1/p' || true)"
case "$iface_index" in
		0) NET4="10.0.0"; NET6_PREFIX="2a01:8b81:4800:9c00:10::" ;;
		1) NET4="10.1.0"; NET6_PREFIX="2a01:8b81:4800:9c00:11::" ;;
		2) NET4="10.2.0"; NET6_PREFIX="2a01:8b81:4800:9c00:12::" ;;
		3) NET4="10.3.0"; NET6_PREFIX="2a01:8b81:4800:9c00:13::" ;;
		4) NET4="10.4.0"; NET6_PREFIX="2a01:8b81:4800:9c00:14::" ;;
		5) NET4="10.5.0"; NET6_PREFIX="2a01:8b81:4800:9c00:15::" ;;
		6) NET4="10.6.0"; NET6_PREFIX="2a01:8b81:4800:9c00:16::" ;;
		7) NET4="10.7.0"; NET6_PREFIX="2a01:8b81:4800:9c00:17::" ;;
		*) err "unsupported iface index: $iface_index"; exit 1 ;;
esac

# ---------- Occupancy from existing map ----------
used_indices=""
if [ -f "$MAP_FILE" ]; then
		map_tmp2="$(mktemp "/tmp/client-map.map2.XXXXXX")"; TMPFILES="$TMPFILES $map_tmp2"
		read_map_lines "$MAP_FILE" > "$map_tmp2"
		while IFS=, read -r mbase miface m4 m6; do
				[ "$miface" = "$IFACE" ] || continue
				case "$m4" in
						*.*.*.*/*) last_octet="$(printf '%s' "$m4" | sed -E 's/.*\.([0-9]+)\/.*/\1/')";;
						*.*.*.*) last_octet="$(printf '%s' "$m4" | sed -E 's/.*\.([0-9]+)$/\1/')";;
						*) last_octet="";;
				esac
				if [ -n "$last_octet" ]; then
						idx=$((last_octet - HOST_OFFSET))
						if [ "$idx" -ge 0 ] 2>/dev/null && [ "$idx" -lt "$USABLE_HOSTS" ] 2>/dev/null; then
								used_indices="${used_indices} ${idx}"
						fi
				fi
				: "$m6"
		done < "$map_tmp2"
fi

# ---------- Canonical allocation ----------
TMP_NEW_MAP="$(mktemp "/tmp/client-map.new.${IFACE}.XXXXXX")"; TMPFILES="$TMPFILES $TMP_NEW_MAP"
: > "$TMP_NEW_MAP"
for name in $(printf '%s\n' "$all_bases"); do
		start="$(alloc_index "$name" "$USABLE_HOSTS")"
		i="$start"; tried=0; found=0
		while [ "$tried" -lt "$USABLE_HOSTS" ]; do
				case " $used_indices " in
						*" $i "*) ;;
						*) found=1; break ;;
				esac
				i=$(( (i + 1) % USABLE_HOSTS ))
				tried=$((tried + 1))
		done
		if [ "$found" -ne 1 ]; then
				rm -f "$TMP_NEW_MAP"
				err "no free host slot found for iface $IFACE"
				exit 1
		fi
		host_octet=$((i + HOST_OFFSET))
		ipv4="${NET4}.${host_octet}/32"
		ipv6="${NET6_PREFIX}${host_octet}/128"
		printf '%s,%s,%s,%s\n' "$name" "$IFACE" "$ipv4" "$ipv6" >> "$TMP_NEW_MAP"
		used_indices="${used_indices} ${i}"
done

# ---------- Compare with old map for this iface ----------
TMP_OLD_MAP="$(mktemp "/tmp/client-map.old.${IFACE}.XXXXXX")"; TMPFILES="$TMPFILES $TMP_OLD_MAP"
: > "$TMP_OLD_MAP"
if [ -f "$MAP_FILE" ]; then
		awk -F, -v iface="$IFACE" 'BEGIN{OFS=","} $2==iface {print $1,$2,$3,$4}' "$MAP_FILE" > "$TMP_OLD_MAP" || true
fi

reassign_diff="$(mktemp "/tmp/client-map.diff.${IFACE}.XXXXXX")"; TMPFILES="$TMPFILES $reassign_diff"
if ! diff -u "$TMP_OLD_MAP" "$TMP_NEW_MAP" > "$reassign_diff" 2>/dev/null; then
		changed=0
		while IFS=, read -r obase oiface o4 o6; do
				if ! grep -F -x -q "${obase},${oiface},${o4},${o6}" "$TMP_NEW_MAP" 2>/dev/null; then
						changed=1; break
				fi
		done < "$TMP_OLD_MAP"
		if [ "$changed" -eq 1 ] && [ "$FORCE_REASSIGN" -ne 1 ]; then
				err "ERROR: allocation would reassign existing clients for $IFACE. Set FORCE_REASSIGN=1 to allow."
				sed -n '1,200p' "$reassign_diff" >&2 || true
				rm -f "$TMP_NEW_MAP" "$TMP_OLD_MAP" "$reassign_diff"
				exit 1
		fi
fi
rm -f "$reassign_diff" 2>/dev/null || true

# ---------- Merge new iface lines into global map atomically ----------
if [ -f "$MAP_FILE" ]; then
		TSTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
		BACKUP_PATH="${BACKUP_DIR%/}/wg-map-${TSTAMP}.tar.gz"
		run_root "mkdir -p '$(dirname "$BACKUP_PATH")' && tar -czf '$BACKUP_PATH' -C '$(dirname "$MAP_FILE")' '$(basename "$MAP_FILE")' 2>/dev/null || true"
fi

TMP_MERGED="$(mktemp "/tmp/client-map.merged.XXXXXX")"; TMPFILES="$TMPFILES $TMP_MERGED"
: > "$TMP_MERGED"
if [ -f "$MAP_FILE" ]; then
		awk -F, -v iface="$IFACE" 'BEGIN{OFS=","} $2!=iface {print $1,$2,$3,$4}' "$MAP_FILE" >> "$TMP_MERGED" || true
fi
cat "$TMP_NEW_MAP" >> "$TMP_MERGED"
atomic_move_as_root "$TMP_MERGED" "$MAP_FILE"

# ---------- Determine which bases are new ----------
old_bases_list="$(awk -F, -v iface="$IFACE" '$2==iface {print $1}' "$TMP_OLD_MAP" 2>/dev/null || true)"
new_bases_list="$(awk -F, -v iface="$IFACE" '$2==iface {print $1}' "$TMP_NEW_MAP" 2>/dev/null || true)"

to_create=""
for nb in $(printf '%s\n' "$new_bases_list"); do
		found=0
		for ob in $(printf '%s\n' "$old_bases_list"); do
				[ "$nb" = "$ob" ] && found=1 && break
		done
		if [ "$found" -eq 0 ]; then
				to_create="${to_create}
${nb}"
		fi
done

if printf '%s\n' "$old_bases_list" | grep -qx "$BASE" 2>/dev/null; then
		to_create="$(printf '%s\n%s\n' "$to_create" "$BASE" | sort -u)"
fi

# ---------- Generate client files sequentially ----------
for b in $(printf '%s\n' "$to_create" | sed '/^[[:space:]]*$/d'); do
		line="$(awk -F, -v b="$b" -v iface="$IFACE" '$1==b && $2==iface {print; exit}' "$TMP_NEW_MAP" 2>/dev/null || true)"
		if [ -z "$line" ]; then err "no mapping for $b $IFACE"; continue; fi
		ipv4="$(printf '%s' "$line" | awk -F, '{print $3}')"
		ipv6="$(printf '%s' "$line" | awk -F, '{print $4}')"

		confname="${b}-${IFACE}"
		key_file="${WG_DIR}/${confname}.key"
		pub_file="${WG_DIR}/${confname}.pub"
		conf_file="${WG_DIR}/${confname}.conf"

		if [ -f "$key_file" ] && [ "$FORCE" -ne 1 ]; then
				printf '🔒 %s exists\n' "$key_file"
		else
				run_root "$WG_BIN genkey | tee '$key_file' | $WG_BIN pubkey > '$pub_file'"
				run_root "chmod 600 '$key_file' '$pub_file'"
		fi

		privkey="$(run_root "cat '$key_file' 2>/dev/null" || true)"
		pubkey="$(run_root "cat '$pub_file' 2>/dev/null" || true)"

		if [ -f "$conf_file" ] && [ "$CONF_FORCE" -ne 1 ]; then
				printf '⏭ %s exists\n' "$conf_file"
		else
				tmp="$(mktemp "${conf_file}.tmp.XXXXXX")"; TMPFILES="$TMPFILES $tmp"
				{
						printf '%s\n' '[Interface]'
						printf 'PrivateKey = %s\n' "$privkey"
						if [ -n "$ipv6" ]; then
								printf 'Address = %s, %s\n' "$ipv4" "$ipv6"
						else
								printf 'Address = %s\n' "$ipv4"
						fi
				} > "$tmp"
				atomic_move_as_root "$tmp" "$conf_file"
		fi

		if run_root "grep -qE '^[[:space:]]*Address[[:space:]]*=' '$conf_file' 2>/dev/null"; then
				run_root "sed -i -E 's|^[[:space:]]*Address[[:space:]]*=.*|Address = ${ipv4}${ipv6:+, $ipv6}|' '$conf_file'"
		else
				run_root "printf '%s\n' 'Address = ${ipv4}${ipv6:+, $ipv6}' >> '$conf_file'"
		fi

		if [ -n "$pubkey" ] && run_root "test -f '$SERVER_CONF'"; then
				ALLOWED="${ipv4}${ipv6:+, $ipv6}"
				lockdir="/var/lock/wg-${IFACE}.lock"
				if acquire_lock "$lockdir"; then
						if ! run_root "grep -qF '$pubkey' '$SERVER_CONF' 2>/dev/null"; then
								run_root "printf '\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s\n' '$confname' '$pubkey' '$ALLOWED' | tee -a '$SERVER_CONF' > /dev/null"
								printf '➕ appended peer %s to %s\n' "$confname" "$SERVER_CONF"
						else
								printf '✅ peer %s already present in %s\n' "$confname" "$SERVER_CONF"
						fi
						if run_root "$WG_BIN set $IFACE peer '$pubkey' allowed-ips '$ALLOWED' 2>/dev/null"; then
								printf '🔧 kernel programmed for %s (AllowedIPs=%s)\n' "$confname" "$ALLOWED"
						else
								err "WARN: wg set failed for $confname; wg-add-peers can reconcile later"
						fi
						release_lock "$lockdir"
				else
						err "failed to acquire lock for $IFACE; skipping kernel programming for $confname"
				fi
		else
				printf '⚠ server conf %s not found or pubkey missing; skipping server programming for %s\n' "$SERVER_CONF" "$confname"
		fi
done

# Cleanup (trap will run cleanup on exit)
for t in $TMPFILES; do
		[ -n "$t" ] || continue
		rm -f -- "$t" 2>/dev/null || true
done

printf '✅ gen-client: completed for %s on %s\n' "$BASE" "$IFACE"
exit 0
