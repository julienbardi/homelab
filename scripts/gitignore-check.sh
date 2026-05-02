#!/bin/sh
# gitignore invariants check (single-shell, POSIX)

printf "🔍 Checking .gitignore invariants...\n"

errors=0
paths=". .vscode/settings.json plan.tsv alloc.tsv keys.tsv mk"

# Batch query
out=$(printf "%s\n" $paths | git check-ignore --stdin 2>/dev/null || true)

for p in $paths; do
    case "$p" in
        .)
            printf "%s\n" "$out" | grep -Fqx "./" && {
                printf "❌ repository root is ignored\n"
                errors=1
            }
            ;;
        .vscode/settings.json)
            printf "%s\n" "$out" | grep -Fqx "$p" && {
                printf "❌ .vscode/settings.json is ignored\n"
                errors=1
            }
            ;;
        mk)
            printf "%s\n" "$out" | grep -Fqx "$p" && {
                printf "❌ mk/ directory is ignored\n"
                errors=1
            }
            ;;
        *)
            printf "%s\n" "$out" | grep -Fqx "$p" || {
                printf "❌ %s is not ignored\n" "$p"
                errors=1
            }
            ;;
    esac
done

if [ "$errors" -ne 0 ]; then
    printf "❌ .gitignore invariants FAILED\n"
    exit 1
fi

printf "✅ .gitignore invariants OK\n"
