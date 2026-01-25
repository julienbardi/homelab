#!/bin/sh
# router-sync-scripts.sh
#
# Contract:
# - The repo directory 10.89.12.1/jffs/scripts/ is authoritative
#   for those files only.
# - Router-only files are ignored and never deleted.
# - This tool overwrites router files that exist in the repo.
# - Rollback is guaranteed via git commit before deployment.

set -eu

HOMELAB_DIR="${HOMELAB_DIR:-$(realpath "$(dirname "$0")/..")}"

router_host="10.89.12.1"
router_user="julie"
router_port="2222"
router_root="/jffs/scripts"

repo_root="$HOMELAB_DIR/10.89.12.1/jffs/scripts"

[ -d "$repo_root" ] || {
	echo "❌ Repo-managed scripts directory missing: $repo_root" >&2
	exit 1
}

# Escape a string for literal use in sed
escape_sed_literal() {
	printf '%s\n' "$1" | sed 's/[\/&]/\\&/g'
}

escaped_repo_root="$(escape_sed_literal "$repo_root")"

tmp_router_snapshot="$(mktemp -d -t router-snapshot.XXXXXX)"
tmp_router_verify="$(mktemp -d -t router-verify.XXXXXX)"
repo_list="$(mktemp -t router-repolist.XXXXXX)"

cleanup() {
	rm -rf "$tmp_router_snapshot" "$tmp_router_verify" "$repo_list"
}

trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

echo "📌 Router: $router_user@$router_host:$router_root"
echo "📌 Repo authority: $repo_root"

# Enumerate repo-managed files once
find "$repo_root" -type f >"$repo_list"

echo "📥 Snapshotting router state (read-only)…"
scp -O -P "$router_port" -r \
	"$router_user@$router_host:$router_root" \
	"$tmp_router_snapshot"

router_snapshot="$tmp_router_snapshot/scripts"

echo "🔍 Comparing repo-managed files against router…"

diff_log="$(mktemp -t router-diff.XXXXXX)"
diff_found=0

while IFS= read -r repo_file; do
	rel=$(printf '%s\n' "$repo_file" | sed "s|^$escaped_repo_root/||")
	router_file="$router_snapshot/$rel"

	if [ ! -f "$router_file" ]; then
		echo "➕ $rel (missing on router)" >>"$diff_log"
	else
		diff -u "$router_file" "$repo_file" >>"$diff_log" || true
	fi
done <"$repo_list"

if [ -s "$diff_log" ]; then
	cat "$diff_log"
	diff_found=1
fi
rm -f "$diff_log"

if [ "$diff_found" -eq 0 ]; then
	echo "✅ No differences detected. Nothing to deploy."
	exit 0
fi

echo
echo "🛑 Deployment gate"
echo "Repo state is authoritative for the files shown above."
echo "Type YES to commit and deploy:"
printf "> "
read -r confirm

if [ "$confirm" != "YES" ]; then
	echo "❌ Aborted."
	exit 1
fi

echo "🧾 Recording authoritative state in git…"
cd "$HOMELAB_DIR"

git add "10.89.12.1/jffs/scripts"

if ! git diff --cached --quiet; then
	git commit -m "router 10.89.12.1: sync /jffs/scripts (authoritative)"
	git push
	git push github main
fi

echo "🚀 Deploying repo-managed files to router…"

while IFS= read -r repo_file; do
	rel=$(printf '%s\n' "$repo_file" | sed "s|^$escaped_repo_root/||")
	remote_path="$router_root/$rel"

	ssh -n -p "$router_port" "$router_user@$router_host" \
		"mkdir -p \"$(dirname "$remote_path")\""

	scp -O -P "$router_port" \
		"$repo_file" \
		"$router_user@$router_host:$remote_path"
done <"$repo_list"

echo "🔎 Verifying deployed state…"
scp -O -P "$router_port" -r \
	"$router_user@$router_host:$router_root" \
	"$tmp_router_verify"

verify_root="$tmp_router_verify/scripts"
verify_failed=0

while IFS= read -r repo_file; do
	rel=$(printf '%s\n' "$repo_file" | sed "s|^$escaped_repo_root/||")
	if ! cmp -s "$repo_file" "$verify_root/$rel"; then
		echo "❌ Verification failed for $rel" >&2
		verify_failed=1
	fi
done <"$repo_list"

[ "$verify_failed" -eq 0 ] || exit 1

echo "✅ Router scripts synchronized successfully."
