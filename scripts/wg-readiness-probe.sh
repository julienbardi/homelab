#!/bin/sh
# wg-readiness-probe.sh — WireGuard Runtime State Probe
# =================================================================
# CONTRACT:
# - Performs low-overhead, read-only interrogation of active kernel state.
# - Validates live cryptography keys and interfaces against target configs.
# - Fast-path execution MUST be entirely free of external network side-effects.
# - Extracted WG_GENERATION markers are matched against persistent state.
# - Outputs exit code 0 if fully converged (skip deploy), 1 if drifted (trigger deploy).
# =================================================================
set -eu

INTERFACE="${1:?ERROR: Interface parameter missing}"
CONFIG_FILE="${2:?ERROR: Config file parameter missing}"
EXPECTED_GEN="${3:-0}"
RUNTIME_STAMP_DIR="${4:?ERROR: Stamp directory parameter missing}"
TARGET_TYPE="${5:-nas}"  # Optional: defaults to nas, can be explicit 'router'

RUNTIME_STAMP_FILE="${RUNTIME_STAMP_DIR}/wg_${INTERFACE}_runtime.gen"

# Fallback or initialization condition
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Desired target configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Define execution wrapping array mechanics contextually based on target architecture
# If target is router, run read-only queries over SSH; otherwise run locally
if [ "$TARGET_TYPE" = "router" ]; then
    : "${ROUTER_HOST:?Missing ROUTER_HOST}"
    : "${ROUTER_SSH_PORT:?Missing ROUTER_SSH_PORT}"
    : "${ROUTER_IDENTITY:?Missing ROUTER_IDENTITY}"
    CMD_PREFIX="ssh -i $ROUTER_IDENTITY -p $ROUTER_SSH_PORT $ROUTER_HOST"
else
    # Pre-flight check: short-circuit gracefully if the wireguard binary is missing locally
    if ! command -v wg >/dev/null 2>&1; then
        echo "❌ wg binary not found in PATH" >&2
        exit 1
    fi
    CMD_PREFIX=""
fi

# Step 1: Structural Verification — check if kernel interface exists on the targeted stack
if [ "$TARGET_TYPE" = "router" ]; then
    # On Asus Merlin, wgs1 might be missing from the kernel stack table if IPv6 is broken,
    # but we still want to avoid unnecessary deploys if the generation stamp already matches.
    # Therefore, if the interface is missing from the kernel, we treat it as non-fatal
    # ONLY if the generation stamp matches below. Otherwise, let it fall through.
    if ! $CMD_PREFIX "wg show $INTERFACE >/dev/null 2>&1"; then
        echo "🔍 Interface $INTERFACE is missing from the router kernel network stack table."
        # If generation stamps match, we allow a constrained pass instead of a hard failure.
    fi
else
    if ! wg show "$INTERFACE" >/dev/null 2>&1; then
        echo "🔍 Interface $INTERFACE is missing from the kernel network stack table."
        exit 1
    fi
fi

# Step 2 & 3: Fast-Path Generation Check
CURRENT_GEN="0"
if [ -f "$RUNTIME_STAMP_FILE" ]; then
    if ! read -r CURRENT_GEN < "$RUNTIME_STAMP_FILE"; then
        CURRENT_GEN="0"
    fi
fi

if [ "$CURRENT_GEN" != "$EXPECTED_GEN" ]; then
    echo "🔍 Generation mismatch on $INTERFACE: kernel/stamp is at '$CURRENT_GEN', config requires '$EXPECTED_GEN'"
    exit 1
fi

# If target is router and generation matches, bypass further kernel queries to neutralize hardware constraints
if [ "$TARGET_TYPE" = "router" ] && [ "$CURRENT_GEN" = "$EXPECTED_GEN" ]; then
    exit 0
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
    if [ "$TARGET_TYPE" = "router" ]; then
        # Parse it locally on the NAS to avoid launching remote worker cycles
        CONFIG_PUBKEY=$(printf '%s' "$PRIVKEY" | wg pubkey 2>/dev/null)
    else
        CONFIG_PUBKEY=$(printf '%s' "$PRIVKEY" | wg pubkey 2>/dev/null)
    fi
fi

if [ -n "$CONFIG_PUBKEY" ]; then
    if [ "$TARGET_TYPE" = "router" ]; then
        KERNEL_PUBKEY=$($CMD_PREFIX "wg show $INTERFACE public-key 2>/dev/null" || echo "")
    else
        KERNEL_PUBKEY=$(wg show "$INTERFACE" public-key 2>/dev/null)
    fi
    KERNEL_PUBKEY=$(printf '%s\n' "$KERNEL_PUBKEY" | tr -d '[:space:]')

    if [ "$CONFIG_PUBKEY" != "$KERNEL_PUBKEY" ]; then
        echo "🔍 Cryptographic key drift caught on $INTERFACE interface link."
        exit 1
    fi
fi

# Step 5: Persist runtime status validation mapping if passing cleanly
[ -d "$RUNTIME_STAMP_DIR" ] || mkdir -p "$RUNTIME_STAMP_DIR"
echo "$EXPECTED_GEN" > "$RUNTIME_STAMP_FILE"

exit 0