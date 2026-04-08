#!/bin/bash
# scripts/deploy_certificates.sh — ECC-first certificate deploy with RSA fallback

# Prevent issuance from running under sudo re-exec.
# acme.sh refuses to operate when SUDO_* variables are present.
if [[ "${1:-}" == "issue" ]]; then
	if [[ -n "${SUDO_COMMAND:-}" ]] && [[ "$SUDO_COMMAND" == *"$0"* ]]; then
		echo "❌ Issuance must be run from a real root shell (sudo -i), not via sudo re-exec."
		echo "   Run the following instead:"
		echo "     sudo -i"
		echo "     $0 issue"
		exit 1
	fi
fi


# If not running as root, re-exec this script under sudo so subcommands are preserved
if [ "$(id -u)" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

set -euo pipefail

# Router deployment target (control plane)
ROUTER_HOST="${ROUTER_HOST:-julie@10.89.12.1}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"
ROUTER_USER="${ROUTER_USER:-julie}"

HOMELAB_DIR="${HOMELAB_DIR:-$(realpath "$(dirname "$0")/..")}"

# shellcheck disable=SC1091
source "/volume1/homelab/homelab.env"
# shellcheck disable=SC1091
source "/usr/local/bin/common.sh"

ACME="$ACME_HOME/acme.sh"

# Intended SAN contract — authoritative list
# ACME DNS-01 can only solve challenges for zones we control (Infomaniak).
# synology.me is NOT our zone → jam9.synology.me cannot be included.
INTENDED_SANS=(
	"DNS:$DOMAIN"
	"DNS:*.$DOMAIN"
)

usage() {
	echo "Usage: $0 {issue|renew|prepare|deploy <service>|validate <service>|all <service>}"
	echo "Services: caddy headscale dnsdist router qnap"
	echo "Note: DiskStation deployment is now Makefile-native:"
	echo "      → use: make deploy-dsm   or   make all-diskstation"
	echo "      → validation: make validate-dsm   or   make validate-diskstation"
	exit 1
}

service_exists() {
	systemctl status "$1.service" >/dev/null 2>&1
}

days_left() {
	local cert="$1"
	local exp
	exp="$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2)"
	local exp_epoch
	exp_epoch="$(date -d "$exp" +%s)"
	local now_epoch
	now_epoch="$(date +%s)"
	echo $(( (exp_epoch - now_epoch) / 86400 ))
}

extract_sans() {
	local cert="$1"
	openssl x509 -in "$cert" -noout -text \
		| grep -A1 "Subject Alternative Name" \
		| tail -n1 \
		| sed 's/, /\n/g' \
		| sed 's/^[[:space:]]*//'
}

validate_sans() {
	local cert="$1"
	local missing=0

	log "🔍 Validating SAN set for certificate: $cert"

	mapfile -t actual_sans < <(extract_sans "$cert")

	for expected in "${INTENDED_SANS[@]}"; do
		if ! printf '%s\n' "${actual_sans[@]}" | grep -qx "$expected"; then
			log "❌ SAN missing: $expected"
			missing=1
		fi
	done

	if (( missing == 1 )); then
		log "❌ SAN drift detected — certificate does NOT match intended SAN contract"
		log "   Expected SANs:"
		printf '   • %s\n' "${INTENDED_SANS[@]}"
		log "   Actual SANs:"
		printf '   • %s\n' "${actual_sans[@]}"
		exit 1
	fi

	log "✅ SAN set validated — certificate matches intended SANs"
}

detect_rate_limit() {
	local log_output="$1"

	# ACME rate‑limit: too many failed authorizations
	if echo "$log_output" | grep -q "urn:ietf:params:acme:error:rateLimited"; then
		local retry
		retry="$(echo "$log_output" | grep -o 'retry after[^"]*' | sed 's/retry after //')"

		log "⛔ ACME rate limit hit — too many failed authorizations"
		log "   Let’s Encrypt requires a cooldown before retrying."
		log "   Retry allowed after: $retry"
		log "   (This happens when a domain repeatedly fails DNS‑01 validation.)"
		return 1
	fi

	return 0
}

issue() {
	log "🔐 Issuing RSA and ECC certificates for $DOMAIN"

	# RSA
	rsa_output="$("$ACME" --server letsencrypt --issue \
		-d "$DOMAIN" \
		-d "*.$DOMAIN" \
		--dns dns_infomaniak \
		--keylength 4096 \
		--always-force-new-domain-key \
		${ACME_FORCE:+--force} 2>&1)" || true

	detect_rate_limit "$rsa_output" || return 1

	if echo "$rsa_output" | grep -q "Cert success"; then
		log "🔐 RSA certificate issued"
	else
		log "❌ RSA certificate issuance failed"
	fi

	# ECC
	ecc_output="$("$ACME" --server letsencrypt --issue \
		-d "$DOMAIN" \
		-d "*.$DOMAIN" \
		--dns dns_infomaniak \
		--keylength ec-256 \
		--ecc \
		--always-force-new-domain-key \
		${ACME_FORCE:+--force} 2>&1)" || true

	detect_rate_limit "$ecc_output" || return 1

	if echo "$ecc_output" | grep -q "Cert success"; then
		log "🔐 ECC certificate issued"
	else
		log "❌ ECC certificate issuance failed"
	fi
}


renew() {
	[[ -f "$ACME_HOME/.last_renew" ]] && \
	(( $(date +%s) - $(stat -c %Y "$ACME_HOME/.last_renew") < 86400 )) && \
	{ log "⏳ Renewal skipped — last attempt <24h"; return; }

	local acme_force="${ACME_FORCE:-0}"

	if (( acme_force == 1 )); then
		log "ℹ️ ACME_FORCE enabled — bypassing renewal thresholds"
		"$ACME" --renew -d "$DOMAIN" --ecc --force && log "🔐 ECC certificate forcibly renewed"
		"$ACME" --renew -d "$DOMAIN" --force && log "🔐 RSA certificate forcibly renewed"
		return
	fi

	local ecc_check="${SSL_CHAIN_ECC}"
	require_file "$ecc_check"
	local ecc_days; ecc_days="$(days_left "$ecc_check")"

	if (( ecc_days > RENEW_THRESHOLD_DAYS )); then
		log "🔁 ECC certificate valid ${ecc_days}d — skipping renewal"
	else
		log "⏳ ECC certificate within ${ecc_days}d — attempting renewal"
		if "$ACME" --renew -d "$DOMAIN" --ecc; then
			log "🔐 ECC certificate renewed"
		else
			log "🔁 ECC renewal not required"
		fi
	fi

	local rsa_check="${SSL_CHAIN_RSA}"
	require_file "$rsa_check"
	local rsa_days; rsa_days="$(days_left "$rsa_check")"

	if (( rsa_days > RENEW_THRESHOLD_DAYS )); then
		log "🔁 RSA certificate valid ${rsa_days}d — skipping renewal"
	else
		log "⏳ RSA certificate within ${rsa_days}d — attempting renewal"
		if "$ACME" --renew -d "$DOMAIN"; then
			log "🔐 RSA certificate renewed"
		else
			log "🔁 RSA renewal not required"
		fi
	fi
	touch "$ACME_HOME/.last_renew"
}

prepare() {
	log "📦 Preparing canonical certificate store at $SSL_CANONICAL_DIR"
	sudo mkdir -p "$SSL_CANONICAL_DIR"

	# Validate SAN contract before deploying anything
	validate_sans "$SSL_CHAIN_ECC"
	validate_sans "$SSL_CHAIN_RSA"

	for t in ecc rsa; do
		if [[ "$t" == "ecc" ]]; then
			require_file "$SSL_CERT_ECC"  || { log "❌ missing ECC cert: $SSL_CERT_ECC"; exit 1; }
			require_file "$SSL_CHAIN_ECC" || { log "❌ missing ECC chain: $SSL_CHAIN_ECC"; exit 1; }
			require_file "$SSL_KEY_ECC"   || { log "❌ missing ECC key: $SSL_KEY_ECC"; exit 1; }
			sudo cp -f "$SSL_CHAIN_ECC" "$SSL_CANONICAL_DIR/fullchain_ecc.pem"
			sudo cp -f "$SSL_KEY_ECC"   "$SSL_CANONICAL_DIR/privkey_ecc.pem"
		else
			require_file "$SSL_CERT_RSA"  || { log "❌ missing RSA cert: $SSL_CERT_RSA"; exit 1; }
			require_file "$SSL_CHAIN_RSA" || { log "❌ missing RSA chain: $SSL_CHAIN_RSA"; exit 1; }
			require_file "$SSL_KEY_RSA"   || { log "❌ missing RSA key: $SSL_KEY_RSA"; exit 1; }
			sudo cp -f "$SSL_CHAIN_RSA" "$SSL_CANONICAL_DIR/fullchain_rsa.pem"
			sudo cp -f "$SSL_KEY_RSA"   "$SSL_CANONICAL_DIR/privkey_rsa.pem"
		fi
	done

	sudo chmod 0600 "$SSL_CANONICAL_DIR"/privkey_*.pem || true
	sudo chmod 0644 "$SSL_CANONICAL_DIR"/fullchain_*.pem || true
	log "📦 Canonical certificate store updated (ECC + RSA)"
}

deploy_caddy() {
	log "🔐 Deploying ECC TLS material to caddy"
	sudo mkdir -p "$SSL_DEPLOY_DIR_CADDY"

	if ! service_exists caddy; then
		log "⏭️ caddy not installed — skipping TLS deployment"
		return 0
	fi

	local changed=0
	install_files_if_changed_v2 changed \
		"" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$SSL_DEPLOY_DIR_CADDY/fullchain.pem" caddy caddy 0644 \
		"" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$SSL_DEPLOY_DIR_CADDY/privkey.pem"   caddy caddy 0640

	if [ "$changed" -eq 1 ]; then
		reload_service caddy /etc/caddy/Caddyfile
	else
		log "🔁 caddy unchanged (no reload)"
	fi
}

deploy_headscale() {
	log "🔐 Deploying ECC TLS material to headscale"
	sudo mkdir -p "$SSL_DEPLOY_DIR_HEADSCALE"

	if ! service_exists headscale; then
		log "⏭️ headscale not installed — skipping TLS deployment"
		return 0
	fi

	local changed=0
	install_files_if_changed_v2 changed \
		"" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem" headscale headscale 0644 \
		"" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem"   headscale headscale 0640

	if [ "$changed" -eq 1 ]; then
		reload_service headscale /etc/headscale/config.yaml
	else
		log "🔁 headscale unchanged (no reload)"
	fi
}

deploy_dnsdist() {
	log "🔐 Deploying DoH TLS material to dnsdist"
	local DNSDIST_GROUP="_dnsdist"
	local DNSDIST_BASE_DIR="/etc/dnsdist"
	local DNSDIST_CERT_DIR="$DNSDIST_BASE_DIR/certs"

	install -d -m 0750 -o root -g "$DNSDIST_GROUP" "$DNSDIST_BASE_DIR"
	install -d -m 0750 -o root -g "$DNSDIST_GROUP" "$DNSDIST_CERT_DIR"

	if ! service_exists dnsdist; then
		log "ℹ️ [deploy][dnsdist] skipped — service not installed"
		return 0
	fi

	local changed=0
	install_files_if_changed_v2 changed \
		"" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "" "" "$DNSDIST_CERT_DIR/fullchain.pem" root "$DNSDIST_GROUP" 0644 \
		"" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "" "" "$DNSDIST_CERT_DIR/privkey.pem"   root "$DNSDIST_GROUP" 0640

	if [ "$changed" -eq 1 ]; then
		log "🔄 Restarting dnsdist (TLS material updated)"
		systemctl restart dnsdist
	else
		log "🔁 dnsdist unchanged (no restart)"
	fi
}

deploy_router() {
	log "🔐 Deploying ECC TLS material to router"

	if ! timeout 5 ssh -p "$ROUTER_SSH_PORT" -o BatchMode=yes "$ROUTER_HOST" true; then
		log "❌ Router unreachable — TLS deployment aborted"
		return 1
	fi

	local changed=0
	install_files_if_changed_v2 changed \
		"" "" "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "$ROUTER_HOST" "$ROUTER_SSH_PORT" "/jffs/ssl/fullchain.pem" "$ROUTER_USER" root 0644 \
		"" "" "$SSL_CANONICAL_DIR/privkey_ecc.pem"   "$ROUTER_HOST" "$ROUTER_SSH_PORT" "/jffs/ssl/privkey.pem"   "$ROUTER_USER" root 0600

	if [ "$changed" -eq 1 ]; then
		log "🔐 Router ECC certificate updated"
	else
		log "🔁 router ECC cert unchanged"
	fi
}

deploy_qnap() {
	log "[deploy][qnap] ECC cert to QNAP"
	# Placeholder for QNAP logic using shifted logic if required
	log "ℹ️ [qnap] manual update remains the policy for this node"
}

validate_caddy() {
	log "[validate][caddy] ECC handshake"
	echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" -cipher ECDHE-ECDSA-AES128-GCM-SHA256 2>/dev/null | openssl x509 -noout -subject -dates || log "⚠️ ECC handshake failed"
}

dispatch_deploy() {
	case "${1:-}" in
		caddy)       deploy_caddy ;;
		headscale)   deploy_headscale ;;
		dnsdist)     deploy_dnsdist ;;
		router)      deploy_router ;;
		qnap)        deploy_qnap ;;
		*) usage ;;
	esac
}

dispatch_validate() {
	case "${1:-}" in
		caddy)       validate_caddy ;;
		*) usage ;;
	esac
}

case "${1:-}" in
	issue)   issue ;;
	renew)   renew ;;
	prepare) prepare ;;
	deploy)
		[[ $# -eq 2 ]] || usage
		dispatch_deploy "$2"
		;;
	validate)
		[[ $# -eq 2 ]] || usage
		dispatch_validate "$2"
		;;
	all)
		[[ $# -eq 2 ]] || usage
		renew
		prepare
		dispatch_deploy "$2"
		dispatch_validate "$2"
		;;
	*) usage ;;
esac

log "✅ deploy_certificates.sh finished"