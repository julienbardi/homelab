#!/bin/sh
set -eu

echo "🔍 Scanning git-tracked files for secret material..."

# Temporary signature file
tmp_sig="$(mktemp)"
cat <<'EOF' > "$tmp_sig"
-----BEGIN RSA PRIVATE KEY-----
-----BEGIN OPENSSH PRIVATE KEY-----
-----BEGIN EC PRIVATE KEY-----
-----BEGIN DSA PRIVATE KEY-----
-----BEGIN PGP PRIVATE KEY BLOCK-----
age-secret-key-
EOF

errors=0

# Iterate over git-tracked files WITHOUT a pipe (avoids subshell)
git ls-files | while IFS= read -r file; do

    # Skip this script itself
    if [ "$file" = "scripts/secrets-check.sh" ]; then
        continue
    fi

    # Skip binary files (git attribute)
    if git check-attr --stdin binary <<EOF | grep -q 'binary: set'
$file
EOF
    then
        continue
    fi

    # Scan file for any signature
    if grep -F -f "$tmp_sig" -q -- "$file" 2>/dev/null; then
        echo "❌ Secret signature found in: $file"
        errors=1
    fi

done

rm -f "$tmp_sig"

if [ "$errors" -ne 0 ]; then
    echo "❌ Plaintext secret material detected"
    exit 1
fi

echo "✅ No secret material found"
exit 0
