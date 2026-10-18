#!/bin/bash
# deploy_certificates.sh

set -euo pipefail

: "${DOMAIN:?missing DOMAIN (must be exported by Makefile or environment)}"

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
                '' '' "$SSL_CHAIN_ECC"  '' '' "$SSL_CANONICAL_DIR/fullchain_ecc.pem"  root ssl-cert 0644 \
                '' '' "$SSL_KEY_ECC"    '' '' "$SSL_CANONICAL_DIR/privkey_ecc.pem"    root ssl-cert 0640 \
                '' '' "$SSL_CHAIN_RSA"  '' '' "$SSL_CANONICAL_DIR/fullchain_rsa.pem"  root root 0644 \
                '' '' "$SSL_KEY_RSA"    '' '' "$SSL_CANONICAL_DIR/privkey_rsa.pem"    root root 0600

            echo \"\$changed\"
        "
    )

    if [[ "$changed" -eq 1 ]]; then
        log "📝 Canonical certificate store at $SSL_CANONICAL_DIR updated"
    else
        log "ℹ️ Canonical certificate store at $SSL_CANONICAL_DIR already up-to-date"
    fi
}

deploy_remote_fastpath() {
    local host="$1"
    local port="$2"
    local remote_fc="$3"
    local remote_pk="$4"

    local canon_fc="$SSL_CANONICAL_DIR/fullchain_ecc.pem"
    local canon_pk="$SSL_CANONICAL_DIR/privkey_ecc.pem"

    local h1 h2
    local h3 h4
    local h5 h6

    h1=$(hash_file "$canon_fc")
    h2=$(hash_file "$canon_pk")

    # Legacy deployment location
    h3=$( (hash_remote "$host" "$port" "$remote_fc" "$SSH_IDENTITY") || echo none )
    h4=$( (hash_remote "$host" "$port" "$remote_pk" "$SSH_IDENTITY") || echo none )

    # ASUS upload store
    h5=$( (hash_remote "$host" "$port" "/jffs/.cert/cert.pem" "$SSH_IDENTITY") || echo none )
    h6=$( (hash_remote "$host" "$port" "/jffs/.cert/key.pem" "$SSH_IDENTITY") || echo none )

    if fastpath_match "$h1" "$h3" \
        && fastpath_match "$h2" "$h4" \
        && fastpath_match "$h1" "$h5" \
        && fastpath_match "$h2" "$h6"; then

        log "ℹ️ Remote TLS material up-to-date (/jffs/ssl + /jffs/.cert)"
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
        log " caddy not installed — skipping"
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
        log "ℹ️ caddy TLS material already up-to-date"
    fi
}

# --------------------------------------------------------------------
# Deploy: headscale
# --------------------------------------------------------------------
deploy_headscale() {
    log "🔐 Deploying ECC TLS to headscale"
    run_as_root mkdir -p "$SSL_DEPLOY_DIR_HEADSCALE"

    local changed=0
    run_as_root install_files_if_changed_v3.sh changed \
        "" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem" headscale headscale 0644 \
        "" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem"   headscale headscale 0640

    if [[ "$changed" -eq 1 ]]; then
        log "📝 headscale TLS material updated"
        reload_service headscale /etc/headscale/config.yaml
    else
        log "ℹ️ headscale TLS material already up-to-date"
    fi
}

# --------------------------------------------------------------------
# Deploy: dnsdist
# --------------------------------------------------------------------
deploy_dnsdist() {
    log "🔐 Deploying ECC TLS to dnsdist"

    run_as_root sh -c "
        install -d -m 0750 -o root -g _dnsdist /etc/dnsdist
        install -d -m 0750 -o root -g _dnsdist /etc/dnsdist/certs

        changed=0

        install_files_if_changed_v3.sh changed \
            \"\" \"\" \"$SSL_CANONICAL_DIR/fullchain_ecc.pem\" \"\" \"\" \"/etc/dnsdist/certs/fullchain.pem\" root _dnsdist 0644 \
            \"\" \"\" \"$SSL_CANONICAL_DIR/privkey_ecc.pem\"   \"\" \"\" \"/etc/dnsdist/certs/privkey.pem\"   root _dnsdist 0640

        if [ \"\$changed\" -eq 1 ]; then
            echo \"📝 dnsdist TLS material updated\" >&2
            systemctl restart dnsdist
        else
            echo \"ℹ️ dnsdist TLS material already up-to-date\" >&2
        fi
    "
}

router_ssh() {
    ssh \
        -p "$ROUTER_SSH_PORT" \
        -i "$SSH_IDENTITY" \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" \
        "$@"
}

get_router_https_fingerprint() {
    echo | openssl s_client \
        -connect "${ROUTER_ADDR}:8443" \
        -servername "$DOMAIN" \
        2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 \
    | cut -d= -f2
}

get_canonical_fingerprint() {
    openssl x509 \
        -in "$SSL_CANONICAL_DIR/fullchain_ecc.pem" \
        -noout \
        -fingerprint \
        -sha256 \
    | cut -d= -f2
}

detect_router_model() {
    router_ssh 'nvram get productid' | tr -d "\r" | head -n1
}

deploy_router_files() {
    router_ssh 'mkdir -p /jffs/.cert'

    local changed=0

    run_as_root install_files_if_changed_v3 changed \
        "" "22" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" "$ROUTER_SSH_PORT" "/jffs/ssl/fullchain.pem" \
        "$SSH_USER_ROUTER" root 0644 \
        "" "22" "$SSL_CANONICAL_DIR/privkey_ecc.pem" \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" "$ROUTER_SSH_PORT" "/jffs/ssl/privkey.pem" \
        "$SSH_USER_ROUTER" root 0600 \
        "" "22" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" "$ROUTER_SSH_PORT" "/jffs/.cert/cert.pem" \
        "$SSH_USER_ROUTER" root 0644 \
        "" "22" "$SSL_CANONICAL_DIR/privkey_ecc.pem" \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" "$ROUTER_SSH_PORT" "/jffs/.cert/key.pem" \
        "$SSH_USER_ROUTER" root 0600

    if [[ "$changed" -eq 1 ]]; then
        log "📝 Router TLS material updated"
    else
        log "ℹ️ Router TLS material already up-to-date"
    fi
}

activate_router_ax86u() {
    router_ssh '
            mkdir -p /jffs/.cert

            if [ "$(nvram get le_enable)" != "2" ]; then
                nvram set le_enable=2
                nvram commit
            fi

            /usr/sbin/gencert.sh -l 1

            router_fp="$(
                openssl x509 \
                    -in /etc/cert.pem \
                    -noout \
                    -fingerprint \
                    -sha256 |
                cut -d= -f2
            )"

            uploaded_fp="$(
                openssl x509 \
                    -in /jffs/.cert/cert.pem \
                    -noout \
                    -fingerprint \
                    -sha256 |
                cut -d= -f2
            )"

            if [ "$router_fp" != "$uploaded_fp" ]; then
                echo "❌ ASUS certificate activation failed"
                exit 1
            fi
        '

    log "✅ ASUS certificate activation verified"
}

activate_router_ac86u() {
    local fp

    fp="$(
        router_ssh '
                openssl x509 \
                    -in /etc/cert.pem \
                    -noout \
                    -fingerprint \
                    -sha256 |
                cut -d= -f2
            '
    )"

	log "⚠️ RT-AC86U firmware does not support uploaded server certificates"
	log "ℹ️ Active HTTPS certificate fingerprint: $fp"
	log "ℹ️ Canonical certificate deployed successfully"

    return 0
}

validate_router_ax86u() {
    local active_fp
    local canonical_fp

    active_fp="$(get_router_https_fingerprint)"

    canonical_fp="$(get_canonical_fingerprint)"

    if [[ "$active_fp" != "$canonical_fp" ]]; then
        log "❌ Router certificate drift detected"
        log "   canonical: $canonical_fp"
        log "   active   : $active_fp"
        return 1
    fi

    log "✅ Router certificate matches canonical store"
}

validate_router_ac86u() {
    local active_fp
    local canonical_fp

    active_fp="$(get_router_https_fingerprint)" || {
        log "⚠️ AC86U HTTPS unavailable, validation skipped"
        return 0
    }

    canonical_fp="$(get_canonical_fingerprint)"

    log "ℹ️ Canonical certificate : $canonical_fp"
    log "ℹ️ Active HTTPS cert     : $active_fp"

    if [[ "$canonical_fp" == "$active_fp" ]]; then
        log "✅ AC86U serves canonical certificate"
    else
        log "⚠️ AC86U firmware serves a self-generated HTTPS certificate"
        log "ℹ️ This is expected for RT-AC86U firmware"
        log "ℹ️ Canonical certificate deployment completed successfully"
    fi
}

# --------------------------------------------------------------------
# Deploy: router
# --------------------------------------------------------------------
deploy_router() {
    log "🔐 Deploying ECC TLS to router"

    local model

    model="$(detect_router_model)"

    log "ℹ️ ASUS model: $model"

    case "$model" in
        RT-AX86U*|RT-AX86U_PRO*)
            deploy_router_files
            activate_router_ax86u
            ;;
        RT-AC86U*)
            deploy_router_files
            activate_router_ac86u
            ;;
        *)
            log "❌ Unsupported ASUS model: $model"
            return 1
            ;;
    esac
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

# Router GUI runs on 8443.
# Port 443 is Caddy and MUST NOT be used for router certificate validation.
validate_router() {
    log "[validate][router] HTTPS certificate"

    local model

    model="$(detect_router_model)"

    log "ℹ️ ASUS model: $model"

    case "$model" in
        RT-AX86U*|RT-AX86U_PRO*)
            validate_router_ax86u
            ;;
        RT-AC86U*)
            validate_router_ac86u
            ;;
        *)
            log "❌ Unsupported ASUS model: $model"
            return 1
            ;;
    esac
}

# Router GUI runs on 8443.
# Port 443 is Caddy and MUST NOT be used for router certificate validation.
status_router() {
    log "[status][router] Checking router TLS status"

    local router_fp
    local uploaded_fp

    # 1. Check reachability
    if ! ping -c1 -W1 "$ROUTER_ADDR" >/dev/null 2>&1; then
        log "⚠️ Router unreachable via ICMP"
        return 1
    fi

    log "ℹ️ Router reachable via ICMP"

    # 2. Check active certificate fingerprint on router GUI
    router_fp="$(
        echo | openssl s_client \
            -connect "${ROUTER_ADDR}:8443" \
            -servername "$DOMAIN" \
            2>/dev/null \
        | openssl x509 -noout -fingerprint -sha256 \
        | cut -d= -f2
    )" || {
        log "❌ Router TLS handshake failed"
        return 1
    }

    uploaded_fp="$(
        openssl x509 \
            -in "$SSL_CANONICAL_DIR/fullchain_ecc.pem" \
            -noout \
            -fingerprint \
            -sha256 \
        | cut -d= -f2
    )"

    if [[ "$router_fp" == "$uploaded_fp" ]]; then
        log "✅ Router serves canonical certificate"
    else
        log "⚠️ Router certificate drift detected"
        log "   local : $uploaded_fp"
        log "   remote: $router_fp"
    fi

    # 3. Check deployed TLS material
    if deploy_remote_fastpath \
        "${SSH_USER_ROUTER}@${ROUTER_ADDR}" \
        "$ROUTER_SSH_PORT" \
        "/jffs/ssl/fullchain.pem" \
        "/jffs/ssl/privkey.pem"; then

        log "ℹ️ Router TLS material matches canonical store"
    else
        log "⚠️ Router TLS material differs from canonical store"
    fi

    # 4. Verify ASUS upload store exists
    router_ssh '
            test -f /jffs/.cert/cert.pem &&
            test -f /jffs/.cert/key.pem
        ' >/dev/null 2>&1 \
            && log "ℹ️ ASUS certificate upload store present" \
            || log "⚠️ ASUS certificate upload store missing"
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
