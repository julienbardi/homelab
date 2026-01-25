#!/bin/sh
# scripts/router-deploy.sh
set -eu

HOMELAB_DIR="${HOMELAB_DIR:-$(realpath "$(dirname "$0")/..")}"

router_port="2222"
router_user="julie"
router_host="10.89.12.1"
router_remote="/jffs/scripts/setup-subnet-router.sh"

repo_script="$HOMELAB_DIR/scripts/setup-subnet-router.sh"

# Assert local artifact exists and is readable
[ -r "$repo_script" ] || {
    echo "❌ Missing or unreadable local script: $repo_script" >&2
    exit 1
}

tmp_router_before="$(mktemp -t router-before.XXXXXX)"
tmp_router_after="$(mktemp -t router-after.XXXXXX)"
deploy_artifact="$(mktemp -t router-artifact.XXXXXX)"

cleanup() {
    rm -f "$tmp_router_before" "$tmp_router_after" "$deploy_artifact"
}

# Ensure cleanup on normal exit and interruption
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "❌ No SHA-256 tool available (need sha256sum or shasum)." >&2
        exit 1
    fi
}

echo "📌 Repo root: $HOMELAB_DIR"
echo "📌 Local script: $repo_script"
echo "📌 Remote script: ${router_user}@${router_host}:${router_remote}"

# Freeze the exact artifact to be inspected and deployed
cp "$repo_script" "$deploy_artifact"

echo "📥 Fetching deployed router script for inspection…"
scp -P "$router_port" \
    "${router_user}@${router_host}:${router_remote}" \
    "$tmp_router_before"

echo "🔍 Showing drift (inspect carefully)…"
diff -u "$tmp_router_before" "$deploy_artifact" || true

artifact_hash="$(sha256_file "$deploy_artifact")"
expected_prefix="$(printf '%.8s' "$artifact_hash")"

echo "🔐 Inspected artifact hash:"
echo "    $artifact_hash"

echo "🛑 Deployment gate"
echo "Type exactly these 8 characters to deploy:"
echo "    $expected_prefix"
printf "> "
read -r confirm

if [ "$confirm" != "$expected_prefix" ]; then
    echo "❌ Confirmation mismatch. Aborted."
    exit 1
fi

echo "🚀 Deploying inspected artifact to router…"
scp -P "$router_port" \
    "$deploy_artifact" \
    "${router_user}@${router_host}:${router_remote}"

echo "🔎 Verifying router now matches inspected artifact…"
scp -P "$router_port" \
    "${router_user}@${router_host}:${router_remote}" \
    "$tmp_router_after"

if ! cmp -s "$deploy_artifact" "$tmp_router_after"; then
    echo "❌ Verification failed: router file does not match inspected artifact." >&2
    exit 1
fi

echo "🧾 Recording deployment in git…"
cd "$HOMELAB_DIR"
git add scripts/setup-subnet-router.sh
git commit -m "router: deploy setup-subnet-router.sh ($artifact_hash)"
git push
git push github main
