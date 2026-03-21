#!/bin/sh
# gen-client-cert-wrapper.sh
# Usage: gen-client-cert-wrapper.sh CN run_as_root install_path [--force]

set -e

CN="${1:-}"
RUN_AS_ROOT="${2:-}"
INSTALL_PATH="${3:-}"
FORCE_FLAG="${4:-}"

if [ -z "$CN" ] || [ -z "$RUN_AS_ROOT" ] || [ -z "$INSTALL_PATH" ]; then
    echo "usage: $0 CN run_as_root install_path [--force]" >&2
    exit 2
fi

GEN_CLIENT_CERT="${INSTALL_PATH}/generate-client-cert.sh"

if [ ! -x "$GEN_CLIENT_CERT" ]; then
    echo "[err] generate-client-cert.sh not found or not executable at $GEN_CLIENT_CERT" >&2
    exit 1
fi

exec $RUN_AS_ROOT "$GEN_CLIENT_CERT" "$CN" $FORCE_FLAG
