#!/bin/bash
# deploy_certificates.sh — optimized, deterministic, fast‑path aware

set -euo pipefail

# --------------------------------------------------------------------
# Environment + safety
# --------------------------------------------------------------------
if [[ "${1:-}" == "issue" ]]; then
    if [[ -n "${SUDO_COMMAND:-}" ]] && [[ "$SUDO_COMMAND" == *"$0"* ]]; then
        echo "❌ Issuance must be run from a real root shell (sudo -i)."
        exit 1
    fi
fi

HOMELAB_DIR="${HOMELAB_DIR:-$(realpath "$(dirname "$0")/..")}"
_henv="/volume1/homelab/homelab.env"

if [[ ! -f "$_henv" ]]; then
    echo "❌ homelab.env not found at $_henv" >&2
    exit 1
fi

# Permissions
_henv_mode=$(stat -c "%a" "$_henv")
_henv_owner=$(stat -c "%u" "$_henv")
_henv_group=$(stat -c "%g" "$_henv")
_admin_gid=$(getent group admin | cut -d: -f3)

group=${_henv_mode:1:1}
other=${_henv_mode:2:1}

if (( group >= 2 )) || (( other >= 2 )); then
    echo "❌ homelab.env is writable by group/others" >&2
    exit 1
fi

if [[ "$_henv_owner" -ne 0 && "$_henv_group" -ne "$_admin_gid" ]]; then
    echo "❌ homelab.env owner must be root or group admin" >&2
    exit 1
fi

unset _henv_mode _henv_owner _henv_group _admin_gid

source "$_henv"
unset _henv

source "/usr/local/bin/common.sh"
SCRIPT_NAME=""

ROUTER_ADDR="${ROUTER_ADDR:-10.89.12.1}"
SSH_USER_ROUTER="${SSH_USER_ROUTER:-root}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"
SSH_OPTS="${SSH_OPTS:-}"

ACME="$ACME_HOME/acme.sh"

INTENDED_SANS=(
    "DNS:$DOMAIN"
    "DNS:*.$DOMAIN"
)

# --------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------
service_exists() {
    systemctl status "$1.service" >/dev/null 2>&1
}

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

hash_remote() {
    ssh -p "$2" -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -F "$HOME/.ssh/config" -i "$HOME/.ssh/id_ed25519" \
        "$1" "sha256sum '$3'" 2>/dev/null | awk '{print $1}'
}

fastpath_match() {
    local local="$1"
    local remote="$2"
    [[ "$local" == "$remote" ]]
}

usage() {
    echo "usage: deploy_certificates.sh {issue|renew|prepare|deploy <service>|validate <service>|status <service>|all <service>}" >&2
    exit 1
}

# --------------------------------------------------------------------
# SAN validation (unchanged)
# --------------------------------------------------------------------
extract_sans() {
    openssl x509 -in "$1" -noout -text \
        | grep -A1 "Subject Alternative Name" \
        | tail -n1 \
        | sed 's/, /\n/g' \
        | sed 's/^[[:space:]]*//'
}

validate_sans() {
    local cert="$1"
    log "🔍 Validating SAN set for $cert"
    mapfile -t actual_sans < <(extract_sans "$cert")
    local missing=0

    for expected in "${INTENDED_SANS[@]}"; do
        if ! printf '%s\n' "${actual_sans[@]}" | grep -qx "$expected"; then
            log "❌ SAN missing: $expected"
            missing=1
        fi
    done

    if (( missing == 1 )); then
        log "❌ SAN drift detected"
        exit 1
    fi

    log "✅ SAN set validated"
}

days_left() {
    local cert="$1"
    local expiry
    expiry=$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)
    local expiry_ts now_ts
    expiry_ts=$(date -d "$expiry" +%s)
    now_ts=$(date +%s)
    echo $(( (expiry_ts - now_ts) / 86400 ))
}

# --------------------------------------------------------------------
# renew — ACME renewal logic (restored)
# --------------------------------------------------------------------
renew() {
    # Skip if last renewal <24h
    if [[ -f "$ACME_HOME/.last_renew" ]] &&
       (( $(date +%s) - $(stat -c %Y "$ACME_HOME/.last_renew") < 86400 )); then
        log "ℹ️ Renewal skipped — last attempt <24h"
        return
    fi

    local acme_force="${ACME_FORCE:-0}"

    if (( acme_force == 1 )); then
        log "ℹ️ ACME_FORCE enabled — forcing renewal"
        "$ACME" --renew -d "$DOMAIN" --ecc --force && log "🔐 ECC certificate forcibly renewed"
        "$ACME" --renew -d "$DOMAIN" --force && log "🔐 RSA certificate forcibly renewed"
        touch "$ACME_HOME/.last_renew"
        return
    fi

    # ECC renewal
    local ecc_days
    ecc_days=$(days_left "$SSL_CHAIN_ECC")
    if (( ecc_days <= RENEW_THRESHOLD_DAYS )); then
        log "ℹ️ ECC certificate within ${ecc_days}d — attempting renewal"
        "$ACME" --renew -d "$DOMAIN" --ecc && log "🔐 ECC certificate renewed" || log "🔄 ECC renewal not required"
    else
        log "🔄 ECC certificate valid ${ecc_days}d — skipping renewal"
    fi

    # RSA renewal
    local rsa_days
    rsa_days=$(days_left "$SSL_CHAIN_RSA")
    if (( rsa_days <= RENEW_THRESHOLD_DAYS )); then
        log "ℹ️ RSA certificate within ${rsa_days}d — attempting renewal"
        "$ACME" --renew -d "$DOMAIN" && log "🔐 RSA certificate renewed" || log "🔄 RSA renewal not required"
    else
        log "🔄 RSA certificate valid ${rsa_days}d — skipping renewal"
    fi

    touch "$ACME_HOME/.last_renew"
}

# --------------------------------------------------------------------
# prepare — canonical store + no redundant work
# --------------------------------------------------------------------
prepare() {
    log "📦 Preparing canonical certificate store at $SSL_CANONICAL_DIR"
    mkdir -p "$SSL_CANONICAL_DIR"

    validate_sans "$SSL_CHAIN_ECC"
    validate_sans "$SSL_CHAIN_RSA"

    cp -f "$SSL_CHAIN_ECC" "$SSL_CANONICAL_DIR/fullchain_ecc.pem"
    cp -f "$SSL_KEY_ECC"   "$SSL_CANONICAL_DIR/privkey_ecc.pem"

    cp -f "$SSL_CHAIN_RSA" "$SSL_CANONICAL_DIR/fullchain_rsa.pem"
    cp -f "$SSL_KEY_RSA"   "$SSL_CANONICAL_DIR/privkey_rsa.pem"

    chown root:ssl-cert "$SSL_CANONICAL_DIR"/privkey_*.pem || true
    chmod 0640 "$SSL_CANONICAL_DIR"/privkey_*.pem || true
    chmod 0644 "$SSL_CANONICAL_DIR"/fullchain_*.pem || true

    log "📦 Canonical certificate store updated"
}

# --------------------------------------------------------------------
# Fast‑path deploy helpers
# --------------------------------------------------------------------
deploy_local_fastpath() {
    local service="$1"
    local dst_dir="$2"

    local canon_fc="$SSL_CANONICAL_DIR/fullchain_ecc.pem"
    local canon_pk="$SSL_CANONICAL_DIR/privkey_ecc.pem"

    local dst_fc="$dst_dir/fullchain.pem"
    local dst_pk="$dst_dir/privkey.pem"

    local h1 h2 h3 h4
    h1=$(hash_file "$canon_fc")
    h2=$(hash_file "$canon_pk")
    h3=$(hash_file "$dst_fc" 2>/dev/null || echo none)
    h4=$(hash_file "$dst_pk" 2>/dev/null || echo none)

    if fastpath_match "$h1" "$h3" && fastpath_match "$h2" "$h4"; then
        log "ℹ️ $service TLS material up-to-date"
        return 0
    fi

    return 1
}

deploy_remote_fastpath() {
    local host="$1"
    local port="$2"
    local remote_fc="$3"
    local remote_pk="$4"

    local canon_fc="$SSL_CANONICAL_DIR/fullchain_ecc.pem"
    local canon_pk="$SSL_CANONICAL_DIR/privkey_ecc.pem"

    local h1 h2 h3 h4
    h1=$(hash_file "$canon_fc")
    h2=$(hash_file "$canon_pk")
    h3=$(hash_remote "$host" "$port" "$remote_fc" || echo none)
    h4=$(hash_remote "$host" "$port" "$remote_pk" || echo none)

    if fastpath_match "$h1" "$h3" && fastpath_match "$h2" "$h4"; then
        log "ℹ️ Remote TLS material up-to-date"
        return 0
    fi

    return 1
}

# --------------------------------------------------------------------
# Deploy: caddy
# --------------------------------------------------------------------
deploy_caddy() {
    log "🔐 Deploying ECC TLS to caddy"
    sudo mkdir -p "$SSL_DEPLOY_DIR_CADDY"

    if ! service_exists caddy; then
        log "📍 caddy not installed — skipping"
        return 0
    fi

    if deploy_local_fastpath "caddy" "$SSL_DEPLOY_DIR_CADDY"; then
        return 0
    fi

    local changed=0
    install_files_if_changed_v2 changed \
        "" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$SSL_DEPLOY_DIR_CADDY/fullchain.pem" caddy caddy 0644 \
        "" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$SSL_DEPLOY_DIR_CADDY/privkey.pem"   caddy caddy 0640

    if [[ "$changed" -eq 1 ]]; then
        reload_service caddy /etc/caddy/Caddyfile
    fi
}

# --------------------------------------------------------------------
# Deploy: headscale
# --------------------------------------------------------------------
deploy_headscale() {
    log "🔐 Deploying ECC TLS to headscale"
    sudo mkdir -p "$SSL_DEPLOY_DIR_HEADSCALE"

    if ! service_exists headscale; then
        log "📍 headscale not installed — skipping"
        return 0
    fi

    if deploy_local_fastpath "headscale" "$SSL_DEPLOY_DIR_HEADSCALE"; then
        return 0
    fi

    local changed=0
    install_files_if_changed_v2 changed \
        "" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem" headscale headscale 0644 \
        "" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem"   headscale headscale 0640

    if [[ "$changed" -eq 1 ]]; then
        reload_service headscale /etc/headscale/config.yaml
    fi
}

# --------------------------------------------------------------------
# Deploy: dnsdist
# --------------------------------------------------------------------
deploy_dnsdist() {
    log "🔐 Deploying ECC TLS to dnsdist"

    local base="/etc/dnsdist"
    local certdir="$base/certs"
    install -d -m 0750 -o root -g _dnsdist "$base"
    install -d -m 0750 -o root -g _dnsdist "$certdir"

    if ! service_exists dnsdist; then
        log "📍 dnsdist not installed — skipping"
        return 0
    fi

    if deploy_local_fastpath "dnsdist" "$certdir"; then
        return 0
    fi

    local changed=0
    install_files_if_changed_v2 changed \
        "" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$certdir/fullchain.pem" root _dnsdist 0644 \
        "" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$certdir/privkey.pem"   root _dnsdist 0640

    if [[ "$changed" -eq 1 ]]; then
        systemctl restart dnsdist
    fi
}

# --------------------------------------------------------------------
# Deploy: router (fast‑path + IFC)
# --------------------------------------------------------------------
deploy_router() {
    log "🔐 Deploying ECC TLS to router"

    if deploy_remote_fastpath \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" \
        "$ROUTER_SSH_PORT" \
        "/jffs/ssl/fullchain.pem" \
        "/jffs/ssl/privkey.pem"; then
        return 0
    fi

    local rc=0 changed=0
    local CHANGED_EXIT="${INSTALL_IF_CHANGED_EXIT_CHANGED:-3}"

    /usr/local/bin/install_file_if_changed_v3.sh \
        "" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" "$ROUTER_SSH_PORT" "/jffs/ssl/fullchain.pem" \
        "julie" "root" "0644" || rc=$?

    [[ "$rc" -eq "$CHANGED_EXIT" ]] && changed=1
    [[ "$rc" -ne 0 && "$rc" -ne "$CHANGED_EXIT" ]] && exit "$rc"

    rc=0
    /usr/local/bin/install_file_if_changed_v3.sh \
        "" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem" \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" "$ROUTER_SSH_PORT" "/jffs/ssl/privkey.pem" \
        "julie" "root" "0600" || rc=$?

    [[ "$rc" -eq "$CHANGED_EXIT" ]] && changed=1
    [[ "$rc" -ne 0 && "$rc" -ne "$CHANGED_EXIT" ]] && exit "$rc"

    if [[ "$changed" -eq 1 ]]; then
        log "📝 Router TLS material updated"
    else
        log "ℹ️ Router TLS material up-to-date"
    fi
}

# --------------------------------------------------------------------
# Deploy: qnap (unchanged)
# --------------------------------------------------------------------
deploy_qnap() {
    log "[deploy][qnap] ECC cert to QNAP"
    log "ℹ️ [qnap] manual update remains policy"
}

# --------------------------------------------------------------------
# Validation (unchanged)
# --------------------------------------------------------------------
validate_caddy() {
    log "[validate][caddy] ECC handshake"
    echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" \
        -cipher ECDHE-ECDSA-AES128-GCM-SHA256 2>/dev/null \
        | openssl x509 -noout -subject -dates || log "⚠️ ECC handshake failed"
}

validate_router() {
    log "[validate][router] ECC handshake"
    echo | openssl s_client \
        -connect "${ROUTER_ADDR}:443" \
        -servername "$DOMAIN" \
        -cipher ECDHE-ECDSA-AES128-GCM-SHA256 \
        2>/dev/null | openssl x509 -noout -subject -dates \
        || log "⚠️ Router ECC handshake failed"
}

# --------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------
dispatch_deploy() {
    case "$1" in
        caddy)     deploy_caddy ;;
        headscale) deploy_headscale ;;
        dnsdist)   deploy_dnsdist ;;
        router)    deploy_router ;;
        qnap)      deploy_qnap ;;
        *) usage ;;
    esac
}

dispatch_validate() {
    case "$1" in
        caddy)  validate_caddy ;;
        router) validate_router ;;
        *) usage ;;
    esac
}

dispatch_status() {
    case "$1" in
        router) status_router ;;
        *) usage ;;
    esac
}

# --------------------------------------------------------------------
# Main
# --------------------------------------------------------------------
case "${1:-}" in
    issue)   issue ;;
    renew)   renew ;;
    prepare) prepare ;;
    deploy)  [[ $# -eq 2 ]] || usage; dispatch_deploy "$2" ;;
    validate) [[ $# -eq 2 ]] || usage; dispatch_validate "$2" ;;
    status) [[ $# -eq 2 ]] || usage; dispatch_status "$2" ;;
    all)
        [[ $# -eq 2 ]] || usage
        renew
        prepare
        dispatch_deploy "$2"
        dispatch_validate "$2"
        ;;
    *) usage ;;
esac

exit 0
