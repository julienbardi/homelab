#!/bin/bash
# deploy_certificates.sh

set -euo pipefail

# shellcheck disable=SC2034
SCRIPT_NAME=""

COMMON="/usr/local/bin/common.sh"
[[ -f "$COMMON" ]] || { echo "❌ Error: $COMMON not found" >&2; exit 1; }
# shellcheck source=common.sh
# shellcheck disable=SC1091
source "$COMMON"

# ACME_HOME, DOMAIN, SSL_CERT_ECC, SSL_CHAIN_ECC, SSL_KEY_ECC, SSL_CANONICAL_DIR
# are all loaded from homelab.env via common.sh

# --------------------------------------------------------------------
# Environment + safety
# --------------------------------------------------------------------
if [[ "${1:-}" == "issue" ]]; then
    if [[ -n "${SUDO_COMMAND:-}" ]] && [[ "$SUDO_COMMAND" == *"$0"* ]]; then
        echo "❌ Issuance must be run from a real root shell (sudo -i)."
        exit 1
    fi
fi

ROUTER_ADDR="${ROUTER_ADDR:-10.89.12.1}"
SSH_USER_ROUTER="${SSH_USER_ROUTER:-root}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"
SSH_IDENTITY="${SSH_IDENTITY:-$HOME/.ssh/id_ed25519}"

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
    local host="$1"
    local port="$2"
    local path="$3"
    local ident="${4:-$SSH_IDENTITY}"

    ssh -p "$port" \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=yes \
        -i "$ident" \
        "$host" "sha256sum '$path'" 2>/dev/null | awk '{print $1}'
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

if [[ "${1:-}" == "_validate_sans" ]]; then
    validate_sans "$2"
    exit 0
fi

# --------------------------------------------------------------------
# prepare — canonical store + no redundant work
# --------------------------------------------------------------------
prepare() {
    log "📦 Preparing canonical certificate store at $SSL_CANONICAL_DIR"

    # SAN validation (unprivileged)
    run_as_root /usr/local/bin/deploy_certificates.sh _validate_sans "$SSL_CHAIN_ECC"

    # Run vectorized IFCv3 inside a privileged shell and capture 'changed' flag
    changed=$(
        run_as_root sh -c "
            mkdir -p '$SSL_CANONICAL_DIR'

            changed=0

            install_files_if_changed_v3.sh changed \
                '' '' '$SSL_CHAIN_ECC'  '' '' '$SSL_CANONICAL_DIR/fullchain_ecc.pem'  root ssl-cert 0644 \
                '' '' '$SSL_KEY_ECC'    '' '' '$SSL_CANONICAL_DIR/privkey_ecc.pem'    root ssl-cert 0640

            echo \"\$changed\"
        "
    )

    if [[ "$changed" -eq 1 ]]; then
        log "📝 Canonical certificate store at $SSL_CANONICAL_DIR updated"
    else
        log "ℹ️ Canonical certificate store at $SSL_CANONICAL_DIR already up-to-date"
    fi
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
    h3=$( (hash_file "$dst_fc" 2>/dev/null) || echo none)
    h4=$( (hash_file "$dst_pk" 2>/dev/null) || echo none)

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
    h3=$( (hash_remote "$host" "$port" "$remote_fc" "$SSH_IDENTITY") || echo none)
    h4=$( (hash_remote "$host" "$port" "$remote_pk" "$SSH_IDENTITY") || echo none)

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
    run_as_root mkdir -p "$SSL_DEPLOY_DIR_CADDY"

    if ! service_exists caddy; then
        log "📍 caddy not installed — skipping"
        return 0
    fi

    if deploy_local_fastpath "caddy" "$SSL_DEPLOY_DIR_CADDY"; then
        log "ℹ️ caddy TLS material already up-to-date (fast-path)"
        return 0
    fi

    local changed=0
    run_as_root install_files_if_changed_v3.sh changed \
        "" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$SSL_DEPLOY_DIR_CADDY/fullchain.pem" caddy caddy 0644 \
        "" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$SSL_DEPLOY_DIR_CADDY/privkey.pem"   caddy caddy 0640

    if [[ "$changed" -eq 1 ]]; then
        log "📝 caddy TLS material updated"
        reload_service caddy /etc/caddy/Caddyfile
    else
        log "ℹ️ caddy TLS material already up-to-date (slow-path)"
    fi
}

# --------------------------------------------------------------------
# Deploy: headscale
# --------------------------------------------------------------------
deploy_headscale() {
    log "🔐 Deploying ECC TLS to headscale"
    run_as_root mkdir -p "$SSL_DEPLOY_DIR_HEADSCALE"

    if ! service_exists headscale; then
        log "📍 headscale not installed — skipping"
        return 0
    fi

    if deploy_local_fastpath "headscale" "$SSL_DEPLOY_DIR_HEADSCALE"; then
        log "ℹ️ headscale TLS material already up-to-date (fast-path)"
        return 0
    fi

    local changed=0
    run_as_root install_files_if_changed_v3.sh changed \
        "" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem" headscale headscale 0644 \
        "" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem"   headscale headscale 0640

    if [[ "$changed" -eq 1 ]]; then
        log "📝 headscale TLS material updated"
        reload_service headscale /etc/headscale/config.yaml
    else
        log "ℹ️ headscale TLS material already up-to-date (slow-path)"
    fi
}

# --------------------------------------------------------------------
# Deploy: dnsdist
# --------------------------------------------------------------------
deploy_dnsdist() {
    log "🔐 Deploying ECC TLS to dnsdist"

    local base="/etc/dnsdist"
    local certdir="$base/certs"

    run_as_root install -d -m 0750 -o root -g _dnsdist "$base"
    run_as_root install -d -m 0750 -o root -g _dnsdist "$certdir"

    if ! service_exists dnsdist; then
        log "📍 dnsdist not installed — skipping"
        return 0
    fi

    if deploy_local_fastpath "dnsdist" "$certdir"; then
        log "ℹ️ dnsdist TLS material already up-to-date (fast-path)"
        return 0
    fi

    local changed=0
    run_as_root install_files_if_changed_v3.sh changed \
        "" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$certdir/fullchain.pem" root _dnsdist 0644 \
        "" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$certdir/privkey.pem"   root _dnsdist 0640

    if [[ "$changed" -eq 1 ]]; then
        log "📝 dnsdist TLS material updated"
        systemctl restart dnsdist
    else
        log "ℹ️ dnsdist TLS material already up-to-date (slow-path)"
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
        log "ℹ️ router TLS material already up-to-date (fast-path)"
        return 0
    fi
    local changed=0
    run_as_root install_files_if_changed_v2 changed \
        "" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" "$ROUTER_SSH_PORT" "/jffs/ssl/fullchain.pem" \
        julie root 0644 \
        "" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem" \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" "$ROUTER_SSH_PORT" "/jffs/ssl/privkey.pem" \
        julie root 0600
    if [[ "$changed" -eq 1 ]]; then
        log "📝 Router TLS material updated"
    else
        log "ℹ️ Router TLS material already up-to-date (slow-path)"
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

    if echo | openssl s_client \
        -connect "$DOMAIN:443" \
        -servername "$DOMAIN" \
        -cipher ECDHE-ECDSA-AES128-GCM-SHA256 \
        2>/dev/null | openssl x509 -noout -subject -dates; then

        log "✅ caddy ECC certificate validated successfully"
    else
        log "⚠️ caddy ECC handshake failed"
    fi
}

validate_router() {
    log "[validate][router] ECC handshake"

    if echo | openssl s_client \
        -connect "${ROUTER_ADDR}:443" \
        -servername "$DOMAIN" \
        -cipher ECDHE-ECDSA-AES128-GCM-SHA256 \
        2>/dev/null | openssl x509 -noout -subject -dates; then

        log "✅ router ECC certificate validated successfully"
    else
        log "⚠️ router ECC handshake failed"
    fi
}

status_router() {
    log "[status][router] Checking router TLS status"

    # 1. Check reachability
    if ! ping -c1 -W1 "$ROUTER_ADDR" >/dev/null 2>&1; then
        log "⚠️ Router unreachable via ICMP"
    else
        log "ℹ️ Router reachable via ICMP"
    fi

    # 2. Check HTTPS ECC handshake
    if echo | openssl s_client \
        -connect "${ROUTER_ADDR}:443" \
        -servername "$DOMAIN" \
        -cipher ECDHE-ECDSA-AES128-GCM-SHA256 \
        2>/dev/null | openssl x509 -noout -subject -dates; then

        log "✅ Router ECC certificate handshake successful"
    else
        log "⚠️ Router ECC handshake failed"
    fi

    # 3. Check TLS material drift (fast-path)
    if deploy_remote_fastpath \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" \
        "$ROUTER_SSH_PORT" \
        "/jffs/ssl/fullchain.pem" \
        "/jffs/ssl/privkey.pem"; then

        log "ℹ️ Router TLS material matches canonical store"
    else
        log "⚠️ Router TLS material differs from canonical store"
    fi
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
    prepare) prepare ;;
    deploy)  [[ $# -eq 2 ]] || usage; dispatch_deploy "$2" ;;
    validate) [[ $# -eq 2 ]] || usage; dispatch_validate "$2" ;;
    status) [[ $# -eq 2 ]] || usage; dispatch_status "$2" ;;
    _validate_sans)
        [[ $# -eq 2 ]] || usage
        validate_sans "$2"
        ;;
    all)
        [[ $# -eq 2 ]] || usage

        log "ℹ️ Delegating ACME issuance/renewal to acme-issue.service"
        run_as_root systemctl start acme-issue.service || {
            log "❌ Failed to trigger acme-issue.service";
            exit 1;
        }

        prepare
        dispatch_deploy "$2"
        dispatch_validate "$2"
        ;;
    *) usage ;;
esac

exit 0
