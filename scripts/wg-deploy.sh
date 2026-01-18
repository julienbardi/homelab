#!/usr/bin/env bash
# scripts/wg-deploy.sh
set -euo pipefail

WG_ROLE="${WG_ROLE:-nas}"

WG_DIR="/etc/wireguard"
ROOT="/volume1/homelab/wireguard"

PLAN="$ROOT/compiled/plan.tsv"

WG_BIN="/usr/bin/wg"
WG_QUICK="/usr/bin/wg-quick"

SERVER_KEYS_DIR="$ROOT/server-keys"

DRY_RUN="${WG_DRY_RUN:-0}"

die()  { echo "wg-deploy: ERROR: $*" >&2; exit 1; }
need() { [ -e "$1" ] || die "missing required path: $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_IF_CHANGED="${SCRIPT_DIR}/install_if_changed.sh"
[ -x "$INSTALL_IF_CHANGED" ] || die "install_if_changed.sh not found or not executable"

if [ "$DRY_RUN" != "1" ]; then
	LOCKFILE="/run/wg-apply.lock"
	exec {LOCKFD}>"$LOCKFILE" || die "cannot create lock file $LOCKFILE (must run as root)"
	flock -n "$LOCKFD" || die "another wg-apply is already running"
fi

need "$PLAN"
need "$SERVER_KEYS_DIR"

# plan.tsv is strict TSV emitted by wg-compile.sh.
# Validate the first non-comment, non-empty line is the expected header.
awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	!seen {
		seen=1
		if ($1=="base" &&
			$2=="iface" &&
			$3=="slot" &&
			$4=="dns" &&
			$5=="client_addr4" &&
			$6=="client_addr6" &&
			$7=="AllowedIPs_client" &&
			$8=="AllowedIPs_server" &&
			$9=="endpoint" &&
			$10=="server_addr4" &&
			$11=="server_addr6" &&
			$12=="server_routes") exit 0
		exit 1
	}
' "$PLAN" || die "plan.tsv: unexpected header (not strict TSV contract)"

mapfile -t ACTIVE_IFACES < <(
	awk -F'\t' '
		/^#/ { next }
		/^[[:space:]]*$/ { next }
		$1=="base" && $2=="iface" { next }
		{ if ($2 != "") print $2 }
	' "$PLAN" | sort -u
)


[ "${#ACTIVE_IFACES[@]}" -gt 0 ] || die "no interfaces found in plan.tsv"

umask 077

PID="$$"
BASE="$(dirname "$WG_DIR")"
NAME="$(basename "$WG_DIR")"

NEW="$BASE/$NAME.new.$PID"
OLD="$BASE/$NAME.old.$PID"

rm -rf "$NEW" 2>/dev/null || true
mkdir "$NEW"

swapped=0

cleanup() {
	# If we swapped /etc/wireguard and then failed, restore the old directory.
	if [ "$swapped" = "1" ] && [ -d "$OLD" ]; then
		rm -rf "$WG_DIR" 2>/dev/null || true
		mv "$OLD" "$WG_DIR" 2>/dev/null || true
	fi
	# If NEW still exists (failure before swap), remove it.
	rm -rf "$NEW" 2>/dev/null || true

	[ -n "${META_TMP:-}" ] && rm -f "$META_TMP" 2>/dev/null || true
}
trap cleanup EXIT

for dev in "${ACTIVE_IFACES[@]}"; do
	case "$dev" in
		wg[0-9]|wg1[0-5]) ;;
		*) die "invalid iface '$dev'" ;;
	esac

	key_src="$SERVER_KEYS_DIR/$dev.key"
	pub_src="$SERVER_KEYS_DIR/$dev.pub"
	need "$key_src"
	need "$pub_src"

	install -m 644 "$pub_src" "$NEW/$dev.pub"

	priv="$(tr -d '\r\n' <"$key_src")"

	base_conf="$ROOT/out/server/base/$dev.conf"
	need "$base_conf"

	# Sanity-check the private key material (fails loud if corrupted)
	printf '%s' "$priv" | "$WG_BIN" pubkey >/dev/null 2>&1 || die "invalid private key in $key_src"

	# Replace placeholder without delimiter/escape issues
	awk -v priv="$priv" '
		{ gsub(/__REPLACED_AT_DEPLOY__/, priv); print }
	' "$base_conf" >"$NEW/$dev.conf"

	chmod 600 "$NEW/$dev.conf"

	# Append rendered peer stanzas (already validated/compiled upstream)
	peer_dir="$ROOT/out/server/peers/$dev"
	[ -d "$peer_dir" ] || die "missing rendered peer dir: $peer_dir"

	find "$peer_dir" -maxdepth 1 -type f -name '*.conf' -print -quit | grep -q . || die "no rendered peers found in $peer_dir"

	while IFS= read -r peer; do
		cat "$peer" >>"$NEW/$dev.conf"
	done < <(find "$peer_dir" -maxdepth 1 -type f -name '*.conf' -print | sort)

done


# --------------------------------------------------------------------
# Keep-list
# --------------------------------------------------------------------
KEEP="$NEW/last-known-good.list"
: >"$KEEP"

for dev in "${ACTIVE_IFACES[@]}"; do
	echo "$dev.conf" >>"$KEEP"
	echo "$dev.pub"  >>"$KEEP"
done


# --------------------------------------------------------------------
# No-op fast path: if NEW matches current /etc/wireguard, do nothing
# --------------------------------------------------------------------
if [ "$DRY_RUN" != "1" ] && [ -d "$WG_DIR" ]; then
	unchanged=1

	while IFS= read -r rel; do
		[ -n "$rel" ] || continue
		[ -f "$NEW/$rel" ] || die "internal error: missing $NEW/$rel"
		[ -f "$WG_DIR/$rel" ] || { unchanged=0; break; }
		cmp -s "$WG_DIR/$rel" "$NEW/$rel" || { unchanged=0; break; }
	done <"$KEEP"

	# If /etc/wireguard contains extra files outside keep-list (excluding legacy/meta), treat as change.
	if [ "$unchanged" = "1" ]; then
		if find "$WG_DIR" -maxdepth 1 -type f \
			! -name 'last-known-good.list' \
			! -name '.deploy-meta' \
			-print -quit | grep -q .; then
			unchanged=0
		fi
	fi

	if [ "$unchanged" = "1" ]; then
		rm -rf "$NEW" 2>/dev/null || true
		exit 0
	fi
fi

if [ "$DRY_RUN" = "1" ] && [ ! -d "$WG_DIR" ]; then
	echo "🧪 DRY-RUN: /etc/wireguard does not exist yet; showing proposed tree only"
	find "$NEW" -maxdepth 2 -type f | sort
	exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
	echo "🧪 DRY-RUN mode enabled — no changes will be applied"
fi

if [ "$DRY_RUN" != "1" ]; then
	echo "🚀 deploying WireGuard configs atomically"
else
	echo "🧪 DRY-RUN: build + diff only"
fi

if [ "$DRY_RUN" != "1" ]; then
	if [ -d "$WG_DIR" ]; then
		mv "$WG_DIR" "$OLD"
	else
		mkdir -p "$BASE"
		mkdir "$OLD"
	fi

	mv "$NEW" "$WG_DIR"
	swapped=1
else
	echo "🧪 DRY-RUN: skipping /etc/wireguard swap"
fi

if [ "$DRY_RUN" = "1" ] && [ -d "$WG_DIR" ]; then
	echo "🧪 DRY-RUN: diff vs existing /etc/wireguard"
	diff -ruN "$WG_DIR" "$NEW" || true
fi

if [ "$DRY_RUN" = "1" ]; then
	# We intentionally do not touch /etc/wireguard at all in dry-run.
	exit 0
fi

KEEP="$WG_DIR/last-known-good.list"

LEGACY="$WG_DIR/.legacy"
mkdir -p "$LEGACY"
chmod 700 "$LEGACY"

for f in "$OLD"/*; do
	[ -f "$f" ] || continue
	b="$(basename "$f")"
	grep -qx "$b" "$KEEP" || mv "$f" "$LEGACY/"
done

if [ "$DRY_RUN" != "1" ]; then
	for dev in "${ACTIVE_IFACES[@]}"; do

		# Read authoritative server config from plan.tsv (cols 10-12)
		read -r server_addr4 server_addr6 server_routes < <(
			awk -F'\t' -v iface="$dev" '
				/^#/ || /^[[:space:]]*$/ { next }
				$1=="base" && $2=="iface" { next }
				$2!=iface { next }
				{
					if (!seen) { a4=$10; a6=$11; r=$12; seen=1; next }
					if ($10!=a4 || $11!=a6 || $12!=r) { exit 2 }
				}
				END {
					if (!seen) exit 1
					print a4, a6, r
				}
			' "$PLAN"
		) || die "plan.tsv: missing or inconsistent server fields for iface '$dev'"


		[ -n "${server_addr4:-}" ] || die "plan.tsv: missing server_addr4 for iface '$dev'"
		[ -n "${server_addr6:-}" ] || die "plan.tsv: missing server_addr6 for iface '$dev'"

		if ! ip link show "$dev" >/dev/null 2>&1; then
			ip link add "$dev" type wireguard
		fi

		"$WG_BIN" setconf "$dev" <("$WG_QUICK" strip "$dev")

		ip -4 address replace "$server_addr4" dev "$dev"
		ip -6 address replace "$server_addr6" dev "$dev"

		ip link set up dev "$dev"

		# Install server_routes (col 12). Empty means "no routes".
		if [ -n "${server_routes:-}" ]; then
			if [ "$WG_ROLE" != "router" ]; then
				die "refusing to install server_routes on role '$WG_ROLE'"
			fi
			IFS=',' read -r -a routes <<<"$server_routes"
			for cidr in "${routes[@]}"; do
				# trim
				cidr="${cidr#"${cidr%%[![:space:]]*}"}"
				cidr="${cidr%"${cidr##*[![:space:]]}"}"
				[ -n "$cidr" ] || continue

				case "$cidr" in
					*:*/*) ip -6 route replace "$cidr" dev "$dev" ;;
					*.*/*) ip -4 route replace "$cidr" dev "$dev" ;;
					*) die "plan.tsv: invalid server_routes entry '$cidr' for iface '$dev'" ;;
				esac
			done
		fi
	done
else
	echo "🧪 DRY-RUN: skipping wg runtime apply"
fi

rm -rf "$OLD" || true
swapped=0

META="$WG_DIR/.deploy-meta"

META_TMP="$(mktemp)"
{
	echo "timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
	echo "host: $(hostname -f 2>/dev/null || hostname)"
	if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		echo "git_commit: $(git -C "$ROOT" rev-parse --short HEAD)"
	fi
	echo "interfaces:"
	for dev in "${ACTIVE_IFACES[@]}"; do
		echo "  - $dev"
	done
} >"$META_TMP"

# Metadata updates are not failures
"$INSTALL_IF_CHANGED" --quiet "$META_TMP" "$META" root root 600 || true
