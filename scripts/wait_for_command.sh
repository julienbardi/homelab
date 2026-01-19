#!/bin/bash
set -euo pipefail

cmd=("$@")
timeout=10

for i in $(seq 1 "$timeout"); do
    if "${cmd[@]}" >/dev/null 2>&1; then
        exit 0
    fi
    sleep 1
done

echo "❌ Command did not become ready: ${cmd[*]}" >&2
exit 1
