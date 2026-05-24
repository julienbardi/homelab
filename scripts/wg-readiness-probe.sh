#!/bin/sh
# =================================================================----
# bin/wg-readiness-probe.sh — WireGuard Runtime State Probe
# =================================================================----
# CONTRACT:
# - Performs low-overhead, read-only interrogation of active kernel state.
# - Validates live cryptography keys and interfaces against target configs.
# - Fast-path execution MUST be entirely free of external network side-effects.
# - Extracted WG_GENERATION markers are matched against persistent state.
# - Outputs exit code 0 if fully converged (skip deploy), 1 if drifted (trigger deploy).
# =================================================================----
set -eu

INTERFACE="${1:?ERROR: Interface parameter missing}"
CONFIG_FILE="${2:?ERROR: Config file parameter missing}"
EXPECTED_GEN="${3:-0}"
STAMP_DIR="${4:?ERROR: Stamp directory parameter missing}"

STAMP_FILE="${STAMP_DIR}/wg_${INTERFACE}_runtime.gen"

# Fallback or initialization condition
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Desired target configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Pre-flight check: short-circuit gracefully if the wireguard binary is missing
if ! command -v wg >/dev/null 2>&1; then
    echo "❌ wg binary not found in PATH" >&2
    exit 1
fi

# Step 1: Structural Verification — check if kernel interface exists
if ! wg show "$INTERFACE" >/dev/null 2>&1; then
    echo "🔍 Interface $INTERFACE is missing from the kernel network stack table."
    exit 1
fi

# Step 2 & 3: Fast-Path Generation Check
CURRENT_GEN="0"
if [ -f "$STAMP_FILE" ]; then
    if ! read -r CURRENT_GEN < "$STAMP_FILE"; then
        CURRENT_GEN="0"
    fi
fi

if [ "$CURRENT_GEN" != "$EXPECTED_GEN" ]; then
    echo "🔍 Generation mismatch on $INTERFACE: kernel is at '$CURRENT_GEN', config requires '$EXPECTED_GEN'"
    exit 1
fi

# Step 4: Cryptographic validation — parsing config safely without word-splitting landmines
CONFIG_PUBKEY=""
PRIVKEY=""

# Parse configuration variables inline using correct shell case pattern sets
while read -r line; do
    case "$line" in
        *[Pp]ublic[Kk]ey=*)
            CONFIG_PUBKEY="${line#*=}"
            CONFIG_PUBKEY=$(printf '%s\n' "$CONFIG_PUBKEY" | tr -d '[:space:]')
            ;;
        *[Pp]rivate[Kk]ey=*)
            PRIVKEY="${line#*=}"
            PRIVKEY=$(printf '%s\n' "$PRIVKEY" | tr -d '[:space:]')
            ;;
    esac
done < "$CONFIG_FILE"

# Derive public key from private key ONLY if private key exists (saves crypto overhead)
if [ -n "$PRIVKEY" ]; then
    CONFIG_PUBKEY=$(printf '%s' "$PRIVKEY" | wg pubkey 2>/dev/null)
fi

if [ -n "$CONFIG_PUBKEY" ]; then
    KERNEL_PUBKEY=$(wg show "$INTERFACE" public-key 2>/dev/null)
    KERNEL_PUBKEY=$(printf '%s\n' "$KERNEL_PUBKEY" | tr -d '[:space:]')

    if [ "$CONFIG_PUBKEY" != "$KERNEL_PUBKEY" ]; then
        echo "🔍 Cryptographic key drift caught on $INTERFACE interface link."
        exit 1
    fi
fi

# Step 5: Persist runtime status validation mapping if passing cleanly
[ -d "$STAMP_DIR" ] || mkdir -p "$STAMP_DIR"
echo "$EXPECTED_GEN" > "$STAMP_FILE"

exit 0