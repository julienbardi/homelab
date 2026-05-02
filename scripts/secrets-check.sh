#!/bin/sh
# plaintext secrets check (single-shell, POSIX)

printf "🔍 Checking for plaintext secrets...\n"

if ls secrets.tmp.* >/dev/null 2>&1; then
    printf "❌ Plaintext secrets found in repo:\n"
    ls -1 secrets.tmp.*
    printf "❌ Plaintext secrets check FAILED\n"
    exit 1
fi

printf "✅ No plaintext secrets found\n"
