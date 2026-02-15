#!/bin/bash
# scripts/deploy_certificates.sh — ECC-first certificate deploy with RSA fallback
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

usage() {
	echo "Usage: $0 {issue|renew|prepare|deploy <service>|validate <service>|all <service>}"
	echo "Services: caddy headscale dnsdist router diskstation qnap"
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
	exp_epoch="$(date -d "$exp" +%s)" now_epoch="$(date +%s)"
	echo $(( (exp_epoch - now_epoch) / 86400 ))
}

issue() {
	log "🔐 Issuing RSA and ECC certificates for $DOMAIN"
	"$ACME" --server letsencrypt --issue -d "$DOMAIN" -d "*.$DOMAIN" --dns dns_infomaniak --keylength 4096 --force || log "⚠️ RSA certificate issuance failed"
	"$ACME" --server letsencrypt --issue -d "$DOMAIN" -d "*.$DOMAIN" --dns dns_infomaniak --keylength ec-256 --ecc --force || log "⚠️ ECC certificate issuance failed"
}

renew() {
	[[ -f "$ACME_HOME/.last_renew" ]] && \
	(( $(date +%s) - $(stat -c %Y "$ACME_HOME/.last_renew") < 86400 )) && \
	{ log "⏳ Renewal skipped — last attempt <24h"; return; }

	local acme_force="${ACME_FORCE:-0}"

	if (( acme_force == 1 )); then
		log "⚠️ ACME_FORCE enabled — bypassing renewal thresholds"
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

	for t in ecc rsa; do
		if [[ "$t" == "ecc" ]]; then
			# ECC must exist — fail loudly if missing
			require_file "$SSL_CERT_ECC"  || { log "❌ missing ECC cert:   $SSL_CERT_ECC";  exit 1; }
			require_file "$SSL_CHAIN_ECC" || { log "❌ missing ECC chain:  $SSL_CHAIN_ECC"; exit 1; }
			require_file "$SSL_KEY_ECC"   || { log "❌ missing ECC key:    $SSL_KEY_ECC";   exit 1; }

			sudo cp -f "$SSL_CHAIN_ECC" "$SSL_CANONICAL_DIR/fullchain_ecc.pem"
			sudo cp -f "$SSL_KEY_ECC"   "$SSL_CANONICAL_DIR/privkey_ecc.pem"

		else
			# RSA must exist — fail loudly if missing
			require_file "$SSL_CERT_RSA"  || { log "❌ missing RSA cert:   $SSL_CERT_RSA";  exit 1; }
			require_file "$SSL_CHAIN_RSA" || { log "❌ missing RSA chain:  $SSL_CHAIN_RSA"; exit 1; }
			require_file "$SSL_KEY_RSA"   || { log "❌ missing RSA key:    $SSL_KEY_RSA";   exit 1; }

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

	# Capture results from atomic_install
	local res1
	res1=$(atomic_install "$SSL_CANONICAL_DIR/fullchain_ecc.pem" \
						  "$SSL_DEPLOY_DIR_CADDY/fullchain.pem" \
						  "caddy:caddy" 0644)

	local res2
	res2=$(atomic_install "$SSL_CANONICAL_DIR/privkey_ecc.pem" \
						  "$SSL_DEPLOY_DIR_CADDY/privkey.pem" \
						  "caddy:caddy" 0640)

	if ! service_exists caddy; then
		log "⏭️ caddy not installed — skipping TLS deployment"
		return 0
	fi
	# Reload if either changed
	if [[ "$res1" == "changed" || "$res2" == "changed" ]]; then
		reload_service caddy /etc/caddy/Caddyfile
	else
		log "🔁 caddy unchanged (no reload)"
	fi
	log "🔐 caddy TLS material deployed"
}

deploy_headscale() {
	log "🔐 Deploying ECC TLS material to headscale"
	sudo mkdir -p "$SSL_DEPLOY_DIR_HEADSCALE"

	local res1
	res1=$(atomic_install "$SSL_CANONICAL_DIR/fullchain_ecc.pem" \
						  "$SSL_DEPLOY_DIR_HEADSCALE/fullchain.pem" \
						  "headscale:headscale" 0644)

	local res2
	res2=$(atomic_install "$SSL_CANONICAL_DIR/privkey_ecc.pem" \
						  "$SSL_DEPLOY_DIR_HEADSCALE/privkey.pem" \
						  "headscale:headscale" 0640)

	if ! service_exists headscale; then
		log "⏭️ headscale not installed — skipping TLS deployment"
		return 0
	fi
	if [[ "$res1" == "changed" || "$res2" == "changed" ]]; then
		reload_service headscale /etc/headscale/config.yaml
	else
		log "🔁 headscale unchanged (no reload)"
	fi
	log "🔐 headscale TLS material deployed"
}

deploy_dnsdist() {
	log "🔐 Deploying DoH TLS material to dnsdist"

	local DNSDIST_GROUP="_dnsdist"
	local DNSDIST_BASE_DIR="/etc/dnsdist"
	local DNSDIST_CERT_DIR="$DNSDIST_BASE_DIR/certs"

	local SRC_CHAIN="$SSL_CANONICAL_DIR/fullchain_ecc.pem"
	local SRC_KEY="$SSL_CANONICAL_DIR/privkey_ecc.pem"

	require_file "$SRC_CHAIN"
	require_file "$SRC_KEY"

	# Ensure base directory exists and is traversable
	install -d "$DNSDIST_BASE_DIR"
	chown root:"$DNSDIST_GROUP" "$DNSDIST_BASE_DIR"
	chmod 0750 "$DNSDIST_BASE_DIR"

	# Ensure cert directory exists and is readable
	install -d "$DNSDIST_CERT_DIR"
	chown root:"$DNSDIST_GROUP" "$DNSDIST_CERT_DIR"
	chmod 0750 "$DNSDIST_CERT_DIR"

	local rc1 rc2

	/usr/local/bin/install_if_changed.sh \
		"$SRC_CHAIN" "$DNSDIST_CERT_DIR/fullchain.pem" root "$DNSDIST_GROUP" 0644
	rc1="$?"

	/usr/local/bin/install_if_changed.sh \
		"$SRC_KEY" "$DNSDIST_CERT_DIR/privkey.pem" root "$DNSDIST_GROUP" 0640
	rc2="$?"

	if ! service_exists dnsdist; then
		log "[deploy][dnsdist] skipped — service not installed"
		return 0
	fi

	if [[ "$rc1" -eq "$INSTALL_IF_CHANGED_EXIT_CHANGED" || "$rc2" -eq "$INSTALL_IF_CHANGED_EXIT_CHANGED" ]]; then
		log "🔄 Restarting dnsdist (TLS material updated)"
		systemctl restart dnsdist
	else
		log "🔁 dnsdist unchanged (no restart)"
	fi
	log "🔐 dnsdist TLS material deployed"
}

deploy_router() {
	log "🔐 Deploying ECC TLS material to router"

	if ! timeout 5 ssh -p "$ROUTER_SSH_PORT" \
        -o BatchMode=yes -o ConnectTimeout=5 \
        "$ROUTER_HOST" true; then
		log "❌ Router unreachable — TLS deployment aborted"
		return 1
	fi

	# Push cert and key to the router (remote host $ROUTER_HOST, user $ROUTER_USER, group root)
	local res1
	res1=$(atomic_install "$SSL_CANONICAL_DIR/fullchain_ecc.pem" \
						  "/jffs/ssl/fullchain.pem" \
						  "$ROUTER_USER:root" 0644 "$ROUTER_HOST")

	local res2
	res2=$(atomic_install "$SSL_CANONICAL_DIR/privkey_ecc.pem" \
						  "/jffs/ssl/privkey.pem" \
						  "$ROUTER_USER:root" 0600 "$ROUTER_HOST")

	# Only log update if either file changed
	if [[ "$res1" == "changed" || "$res2" == "changed" ]]; then
		log "🔐 Router ECC certificate updated — manual web service restart may be required"
	else
		log "🔁 router ECC cert unchanged"
	fi
}

deploy_diskstation() {
	log "[deploy][diskstation] ECC cert to Synology DSM (default slot)"

	# Ensure target directory exists (with timeout)
	if ! timeout 10 ssh julie@10.89.12.2 "sudo mkdir -p /usr/syno/etc/certificate/system/default"; then
		log "[deploy][diskstation] ❌ Failed to create target directory (timeout or connection error)"
		return 1
	fi

	local res1 res2 res3 res4
	res1=$(timeout 10 atomic_install "$SSL_CANONICAL_DIR/bardi.ch.cer" \
						  "/usr/syno/etc/certificate/system/default/cert.pem" \
						  "julie:root" 0644 10.89.12.2) || { log "[deploy][diskstation] ❌ cert.pem push failed"; return 1; }

	res2=$(timeout 10 atomic_install "$SSL_CANONICAL_DIR/fullchain.cer" \
						  "/usr/syno/etc/certificate/system/default/fullchain.pem" \
						  "julie:root" 0644 10.89.12.2) || { log "[deploy][diskstation] ❌ fullchain.pem push failed"; return 1; }

	res3=$(timeout 10 atomic_install "$SSL_CANONICAL_DIR/ca.cer" \
						  "/usr/syno/etc/certificate/system/default/chain.pem" \
						  "julie:root" 0644 10.89.12.2) || { log "[deploy][diskstation] ❌ chain.pem push failed"; return 1; }

	res4=$(timeout 10 atomic_install "$SSL_CANONICAL_DIR/bardi.ch.key" \
						  "/usr/syno/etc/certificate/system/default/privkey.pem" \
						  "julie:root" 0600 10.89.12.2) || { log "[deploy][diskstation] ❌ privkey.pem push failed"; return 1; }

	if [[ "$res1" == "changed" || "$res2" == "changed" || "$res3" == "changed" || "$res4" == "changed" ]]; then
		log "[deploy][diskstation] ECC cert updated; restarting DSM web service"
		if ! timeout 10 ssh julie@10.89.12.2 'sudo synosystemctl restart nginx'; then
			log "[deploy][diskstation] ❌ Failed to restart DSM web service"
			return 1
		fi
	else
		log "🔁 diskstation ECC cert unchanged"
	fi

	log "[deploy][diskstation] complete"
	# DSM regenerates root.pem and short-chain.pem automatically.
}

deploy_qnap() {
	log "[deploy][qnap] ECC cert to QNAP"
	local ecc_changed="0"
	local h_ecc="/etc/config/ssl/.hash_fullchain_ecc"
	if changed "$SSL_CANONICAL_DIR/fullchain_ecc.pem" "$h_ecc"; then
	ecc_changed="1"
	scp "$SSL_CANONICAL_DIR/fullchain_ecc.pem" admin@192.168.50.3:/etc/config/ssl/fullchain.pem
	scp "$SSL_CANONICAL_DIR/privkey_ecc.pem"   admin@192.168.50.3:/etc/config/ssl/privkey.pem
	fi
	[[ "$ecc_changed" == "1" ]] && log "[qnap] cert updated; restart QTS web service"
}

validate_caddy() {
	log "[validate][caddy] ECC handshake"
	echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" -cipher ECDHE-ECDSA-AES128-GCM-SHA256 2>/dev/null | openssl x509 -noout -subject -dates || log "[warn] ECC handshake failed"
	log "[validate][caddy] RSA handshake (fallback)"
	echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" -cipher ECDHE-RSA-AES128-GCM-SHA256 2>/dev/null | openssl x509 -noout -subject -dates || log "[warn] RSA handshake failed"
}

validate_headscale() { log "[validate][headscale] only if exposed on 443"; }
validate_router() { log "[validate][router] remote validation requires hostnames/ports"; }
validate_diskstation() {
	log "[validate][diskstation] checking certificate served by DSM on 10.89.12.2:5001"

	NAS_CERT="$HOME/.acme.sh/bardi.ch/bardi.ch.cer"

	# Extract NAS expiry + fingerprint
	nas_expiry=$(openssl x509 -in "$NAS_CERT" -noout -enddate | cut -d= -f2)
	nas_epoch=$(date -d "$nas_expiry" +%s)
	nas_fp=$(openssl x509 -in "$NAS_CERT" -noout -fingerprint -sha256)

	# Run s_client with timeout (10s)
	remote_raw=$(timeout 10 openssl s_client -connect 10.89.12.2:5001 -servername bardi.ch </dev/null 2>/dev/null)
	if [[ $? -ne 0 || -z "$remote_raw" ]]; then
		echo "[validate][diskstation] ❌ Failed to retrieve remote certificate (timeout or connection error)"
		return 1
	fi

	# Parse remote cert details
	remote_cert=$(echo "$remote_raw" | openssl x509 -noout -text)
	remote_fp=$(echo "$remote_raw" | openssl x509 -noout -fingerprint -sha256)
	remote_expiry=$(echo "$remote_cert" | grep "Not After" | sed 's/ *Not After : //')
	remote_epoch=$(date -d "$remote_expiry" +%s)
	remote_sans=$(echo "$remote_cert" | grep -A1 "Subject Alternative Name")

	# Log results
	echo "[validate][diskstation] NAS expiry:     $nas_expiry ($nas_epoch)"
	echo "[validate][diskstation] Remote expiry:  $remote_expiry ($remote_epoch)"
	echo "[validate][diskstation] Remote SANs:    $remote_sans"
	echo "[validate][diskstation] NAS fingerprint:     $nas_fp"
	echo "[validate][diskstation] Remote fingerprint:  $remote_fp"

	# Compare fingerprints
	if [[ "$nas_fp" == "$remote_fp" ]]; then
		echo "[validate][diskstation] ✅ Remote cert matches NAS cert"
	else
		echo "[validate][diskstation] ❌ Remote cert does not match NAS cert"
	fi

	# Compare expiry
	if (( nas_epoch > remote_epoch )); then
		echo "[validate][diskstation] ⚠️ NAS cert is newer than remote"
	fi

	log "[validate][diskstation] complete"
}

validate_qnap() { log "[validate][qnap] remote validation requires hostnames/ports"; }

# ------------------------------------------------------------
# Orchestration / Dispatch
# ------------------------------------------------------------

dispatch_deploy() {
	case "${1:-}" in
		caddy)        deploy_caddy ;;
		headscale)    deploy_headscale ;;
		dnsdist)      deploy_dnsdist ;;
		router)       deploy_router ;;
		diskstation)  deploy_diskstation ;;
		qnap)         deploy_qnap ;;
		*) usage ;;
	esac
}

dispatch_validate() {
	case "${1:-}" in
		caddy)        validate_caddy ;;
		headscale)    validate_headscale ;;
		router)       validate_router ;;
		diskstation)  validate_diskstation ;;
		qnap)         validate_qnap ;;
		*) usage ;;
	esac
}

case "${1:-}" in
	issue)      issue ;;
	renew)      renew ;;
	prepare)    prepare ;;
	deploy)
	[[ $# -eq 2 ]] || usage
	case "$2" in
		caddy|headscale|dnsdist|router|diskstation|qnap) ;;
		*) log "[deploy] ERROR: unsupported service '$2'"; exit 2 ;;
	esac
	dispatch_deploy "$2"
	;;
	validate)   [[ $# -eq 2 ]] || usage; dispatch_validate "$2" ;;
	all)
		[[ $# -eq 2 ]] || usage
		renew
		prepare
		dispatch_deploy "$2"
		dispatch_validate "$2"
		;;
	*) usage ;;
esac

# Footer marker for auditability
log "[complete] deploy_certificates.sh finished"
