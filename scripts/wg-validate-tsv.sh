#!/usr/bin/env bash
set -euo pipefail

: "${WG_ROOT:?WG_ROOT not set}"

INPUT="$WG_ROOT/input"

fail() {
	echo "❌ wg-validate-tsv: ERROR: $*" >&2
	exit 1
}

check_file() {
	[ -f "$1" ] || fail "missing $1"
}

check_header() {
	local file="$1"
	local expected="$2"
	local actual

	actual="$(head -n1 "$file" | sed 's/[[:space:]]*$//')"
	expected="$(printf '%s' "$expected" | sed 's/[[:space:]]*$//')"

	[ "$actual" = "$expected" ] || fail "$file header mismatch (expected: '$expected')"
}

check_unique_col() {
	local file="$1"
	local col="$2"

	if awk -F'\t' -v c="$col" 'NR>1 {print $c}' "$file" \
		| sort | uniq -d | grep -q .; then
		fail "duplicate values in $file column $col"
	fi
}

# ---- existence ----
check_file "$INPUT/users.tsv"
check_file "$INPUT/hosts.tsv"
check_file "$INPUT/wg-interfaces.tsv"
check_file "$INPUT/wg-profiles.tsv"
check_file "$INPUT/wg-clients.tsv"

# ---- headers ----
check_header "$INPUT/users.tsv" \
	"user_id	display_name	email	enabled"

check_header "$INPUT/hosts.tsv" \
	"host_id	hostname	mgmt_host	mgmt_port	mgmt_user	locality	enabled"

check_header "$INPUT/wg-interfaces.tsv" \
	"iface	host_id	listen_port	mtu	address_v4	address_v6	enabled"

check_header "$INPUT/wg-profiles.tsv" \
	"profile	lan_access	internet_v4	internet_v6	dns_mode	description	enabled"

check_header "$INPUT/wg-clients.tsv" \
	"client_id	user_id	iface	profile	base	os	enabled"

# ---- uniqueness ----
check_unique_col "$INPUT/users.tsv" 1
check_unique_col "$INPUT/hosts.tsv" 1
check_unique_col "$INPUT/wg-interfaces.tsv" 1
check_unique_col "$INPUT/wg-profiles.tsv" 1
check_unique_col "$INPUT/wg-clients.tsv" 1

echo "✅ wg-validate-tsv: OK"
