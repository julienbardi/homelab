#!/bin/sh
set -eu

echo "🔍 Scanning git-tracked files for secret material..."

errors=0

# ---------------------------------------------------------------------------
# 1. Fixed-string signatures (private keys, PGP, AGE)
# ---------------------------------------------------------------------------

tmp_sig="$(mktemp)"
cat <<'EOF' > "$tmp_sig"
-----BEGIN RSA PRIVATE KEY-----
-----BEGIN OPENSSH PRIVATE KEY-----
-----BEGIN EC PRIVATE KEY-----
-----BEGIN DSA PRIVATE KEY-----
-----BEGIN PGP PRIVATE KEY BLOCK-----
age-secret-key-
EOF

# ---------------------------------------------------------------------------
# 2. Iterate over git-tracked files WITHOUT pipes (avoids subshell)
# ---------------------------------------------------------------------------

while IFS= read -r file; do

    # Skip this script itself
    if [ "$file" = "scripts/secrets-check.sh" ]; then
        continue
    fi

    # Skip binary files
    if git check-attr --stdin binary <<EOF | grep -q 'binary: set'
$file
EOF
    then
        continue
    fi

    # -----------------------------------------------------------------------
    # 2A. Fixed-string signature scan
    # -----------------------------------------------------------------------
    if grep -F -f "$tmp_sig" -q -- "$file" 2>/dev/null; then
        echo "❌ Secret signature found in: $file"
        errors=1
    fi

    # -----------------------------------------------------------------------
    # 2B. Regex-based secret scans
    # -----------------------------------------------------------------------

    # WireGuard keys
    if grep -Eq "^PrivateKey=[A-Za-z0-9+/=]{32,}" -- "$file"; then
        echo "❌ WireGuard PrivateKey found in: $file"
        errors=1
    fi

    if grep -Eq "^PresharedKey=[A-Za-z0-9+/=]{32,}" -- "$file"; then
        echo "❌ WireGuard PresharedKey found in: $file"
        errors=1
    fi

    # GitHub PATs
    if grep -Eq "ghp_[A-Za-z0-9]{30,}" -- "$file"; then
        echo "❌ GitHub PAT found in: $file"
        errors=1
    fi

    if grep -Eq "github_pat_[A-Za-z0-9_]{30,}" -- "$file"; then
        echo "❌ GitHub PAT found in: $file"
        errors=1
    fi

    # Cloudflare / Infomaniak tokens
    if grep -Eq "CF_API|CLOUDFLARE.*(token|key)" -- "$file"; then
        echo "❌ Cloudflare token found in: $file"
        errors=1
    fi

    if grep -Eq "INFOMANIAK.*(token|key)" -- "$file"; then
        echo "❌ Infomaniak token found in: $file"
        errors=1
    fi

    # password= (only flag real password= lines, not passwd=)
    if grep -Eq "^password=[^ ]" -- "$file"; then
        echo "❌ password= found in: $file"
        errors=1
    fi

    # passwd= (whitelist variable references)
    if grep -q "passwd=" -- "$file"; then
        # Allow passwd=$(...), passwd=${...}, passwd=$VAR
        if ! grep -q "passwd=\$(" -- "$file" \
        && ! grep -q "passwd=\${" -- "$file" \
        && ! grep -q "passwd=\$[A-Za-z0-9_]" -- "$file"
        then
            echo "❌ passwd= found in: $file"
            errors=1
        fi
    fi

    # PPPoE credentials
    if grep -Eq "PPPoE.*(user|pass)" -- "$file"; then
        echo "❌ PPPoE credential found in: $file"
        errors=1
    fi

    # SOPS unencrypted blocks
    if grep -Eq "SOPS.*unencrypted" -- "$file"; then
        echo "❌ SOPS unencrypted block found in: $file"
        errors=1
    fi

    # ACME account.key references (whitelist paths and comments)
    if grep -Eq "account\.key" -- "$file"; then
        if ! grep -Eq "/account\.key|account\.key\)" -- "$file"; then
            echo "❌ ACME account.key reference found in: $file"
            errors=1
        fi
    fi

    # Backup / temp files tracked in git
    case "$file" in
        *.bak|*.old|*.orig|*.swp|*.swo)
            echo "❌ Backup/temp file tracked in git: $file"
            errors=1
            ;;
    esac

    # dotenv secrets
    if [ "$(basename "$file")" = ".env" ]; then
        if grep -Eq "^[A-Z0-9_]+=" -- "$file"; then
            echo "❌ .env file with secrets found in: $file"
            errors=1
        fi
    fi

done <<EOF
$(git ls-files)
EOF

rm -f "$tmp_sig"

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------

if [ "$errors" -ne 0 ]; then
    echo "❌ Plaintext secret material detected"
    exit 1
fi

echo "✅ No secret material found"
exit 0
