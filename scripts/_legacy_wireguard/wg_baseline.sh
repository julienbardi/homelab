#!/bin/bash
# ============================================================
# wg-baseline.sh (Gen-3)
# ------------------------------------------------------------
# Baseline initializer for the contract-driven WireGuard system
#
# Responsibilities:
#   - Validate TSV inputs
#   - Ensure server keys exist (idempotent)
#   - Compile plan + keys
#   - Render server + client configs
#   - Export clients (including QR codes)
#   - Produce operator-visible, icon-aligned logs
#
# This script does NOT:
#   - Generate keys manually
#   - Write configs directly
#   - Touch /etc/wireguard
#   - Bypass the compiled plan
# ============================================================

set -euo pipefail
SCRIPT_NAME="wg-baseline"

# shellcheck disable=SC1091
source /usr/local/bin/common.sh

: "${WG_ROOT:?WG_ROOT not set}"

log "ℹ️ Starting WireGuard baseline initialization"
log "ℹ️ WG_ROOT = ${WG_ROOT}"

# ------------------------------------------------------------
# 1) Validate TSV schema
# ------------------------------------------------------------
log "🔍 Validating TSV inputs"
if ! WG_ROOT="${WG_ROOT}" "${WG_ROOT}/scripts/wg-validate-tsv.sh"; then
    log "❌ TSV validation failed — fix input/*.tsv"
    exit 1
fi
log "✅ TSV inputs valid"

# ------------------------------------------------------------
# 2) Ensure server keys exist
# ------------------------------------------------------------
log "🔄 Ensuring server keys"
if ! WG_ROOT="${WG_ROOT}" "${WG_ROOT}/scripts/wg-ensure-server-keys.sh"; then
    log "❌ Failed to ensure server keys"
    exit 1
fi
log "ℹ️ Server keys OK"

# ------------------------------------------------------------
# 3) Compile plan + keys
# ------------------------------------------------------------
log "🔄 Compiling WireGuard plan"
if ! WG_ROOT="${WG_ROOT}" "${WG_ROOT}/scripts/wg-compile.sh"; then
    log "❌ wg-compile failed"
    exit 1
fi

log "🔄 Compiling WireGuard keys"
if ! WG_ROOT="${WG_ROOT}" "${WG_ROOT}/scripts/wg-compile-keys.sh"; then
    log "❌ wg-compile-keys failed"
    exit 1
fi

log "ℹ️ Compilation complete"

# ------------------------------------------------------------
# 4) Render server + client configs
# ------------------------------------------------------------
log "🔄 Rendering server base configs"
if ! WG_ROOT="${WG_ROOT}" "${WG_ROOT}/scripts/wg-render-server-base.sh"; then
    log "❌ Failed to render server base configs"
    exit 1
fi

log "🔄 Rendering missing client configs"
if ! WG_ROOT="${WG_ROOT}" "${WG_ROOT}/scripts/wg-render-missing-clients.sh"; then
    log "❌ Failed to render missing client configs"
    exit 1
fi

log "ℹ️ Rendering complete"

# ------------------------------------------------------------
# 5) Export clients (including QR codes)
# ------------------------------------------------------------
log "🔄 Exporting client configs (with QR codes)"
if ! WG_ROOT="${WG_ROOT}" "${WG_ROOT}/scripts/wg-client-export.sh"; then
    log "❌ Client export failed"
    exit 1
fi

log "ℹ️ Client exports available under ${WG_ROOT}/export/clients"

# ------------------------------------------------------------
# 6) Drift check (optional but recommended)
# ------------------------------------------------------------
log "🔍 Checking for client drift"
if ! WG_ROOT="${WG_ROOT}" "${WG_ROOT}/scripts/wg-clients-drift.sh"; then
    log "⚠️ Drift detected — investigate before deployment"
else
    log "ℹ️ No drift detected"
fi

# ------------------------------------------------------------
# Completion
# ------------------------------------------------------------
log "✅ WireGuard baseline initialization complete"
