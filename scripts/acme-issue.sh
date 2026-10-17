#!/bin/sh
# ------------------------------------------------------------------
# scripts/acme-issue.sh
#
# CONTRACT:
# - Maintains two independent certificate lineages:
#     bardi.ch
#     bardi.ch_ecc
# - ECC is the canonical homelab certificate
# - RSA exists for DSM compatibility
# - Safe to run repeatedly
# - Validates certificate contracts before any ACME operation
# - Issues missing lineages
# - Requests renewal for certificates within the renewal window
# - Refuses silent contract drift
#
# RUNTIME REQUIREMENT:
# - GNU date required for expiry calculations
# ------------------------------------------------------------------

set -eu

ACME_HOME="/var/lib/acme"
PRIMARY_DOMAIN="${DOMAIN:-bardi.ch}"

ECC_LINEAGE="$ACME_HOME/${PRIMARY_DOMAIN}_ecc"
RSA_LINEAGE="$ACME_HOME/${PRIMARY_DOMAIN}"

ECC_CERT="$ECC_LINEAGE/fullchain.cer"
ECC_KEY="$ECC_LINEAGE/${PRIMARY_DOMAIN}.key"

RSA_CERT="$RSA_LINEAGE/fullchain.cer"
RSA_KEY="$RSA_LINEAGE/${PRIMARY_DOMAIN}.key"

RENEW_MARGIN_DAYS=60
RENEW_MARGIN_SECS=$((RENEW_MARGIN_DAYS * 24 * 60 * 60))

# ------------------------------------------------------------------
# Validate certificate contract
#
# Arguments:
#   $1 cert
#   $2 key
#   $3 ecc|rsa
#   $4 variable prefix (ECC|RSA)
# ------------------------------------------------------------------
validate_cert() {
	cert="$1"
	key="$2"
	alg="$3"
	prefix="$4"

	echo "🔍 validating $cert"

	[ -f "$cert" ] || {
		echo "⚠️ missing certificate: $cert"
		return 1
	}

	[ -f "$key" ] || {
		echo "⚠️ missing key: $key"
		return 1
	}

	openssl x509 \
		-in "$cert" \
		-noout >/dev/null 2>&1 || {
		echo "⚠️ certificate unreadable"
		return 1
	}

	openssl x509 \
		-checkend "$RENEW_MARGIN_SECS" \
		-noout \
		-in "$cert" >/dev/null 2>&1 || {
		echo "🔄 certificate expires within ${RENEW_MARGIN_DAYS} days, renewal required"
		return 1
	}

	sans="$(
		openssl x509 \
			-in "$cert" \
			-noout \
			-ext subjectAltName 2>/dev/null
	)"

	echo "$sans" | grep -F 'DNS:bardi.ch' >/dev/null || {
		echo "⚠️ missing SAN bardi.ch"
		return 1
	}

	echo "$sans" | grep -F 'DNS:*.bardi.ch' >/dev/null || {
		echo "⚠️ missing SAN *.bardi.ch"
		return 1
	}

	echo "$sans" | grep -F 'DNS:*.lan.bardi.ch' >/dev/null || {
		echo "⚠️ missing SAN *.lan.bardi.ch"
		return 1
	}

	cert_pub="$(
		openssl x509 -in "$cert" -pubkey -noout |
		openssl pkey -pubin -outform PEM 2>/dev/null |
		openssl sha256 |
		awk '{print $2}'
	)"

	key_pub="$(
		openssl pkey -in "$key" -pubout -outform PEM 2>/dev/null |
		openssl sha256 |
		awk '{print $2}'
	)"

	[ "$cert_pub" = "$key_pub" ] || {
		echo "⚠️ certificate/key mismatch"
		return 1
	}

	case "$alg" in
		ecc)
			openssl x509 -in "$cert" -text -noout |
			grep -q 'id-ecPublicKey' || {
				echo "⚠️ expected ECC certificate"
				return 1
			}
			;;
		rsa)
			openssl x509 -in "$cert" -text -noout |
			grep -q 'Public-Key: (4096 bit)' || {
				echo "⚠️ expected RSA-4096 certificate"
				return 1
			}
			;;
	esac

	san_list="$(
		echo "$sans" |
		grep -v '^X509v3' |
		sed 's/^[[:space:]]*//'
	)"

	subject="$(
		openssl x509 -in "$cert" -noout -subject |
		sed 's/^subject=//'
	)"

	issuer="$(
		openssl x509 -in "$cert" -noout -issuer |
		sed 's/^issuer=//'
	)"

	expiry="$(
		openssl x509 -in "$cert" -noout -enddate |
		cut -d= -f2-
	)"

	fingerprint="$(
		openssl x509 \
			-in "$cert" \
			-noout \
			-fingerprint \
			-sha256 |
		cut -d= -f2
	)"

	days_remaining="$(
		exp_epoch=$(
			openssl x509 -in "$cert" -noout -enddate |
			sed 's/^notAfter=//;s/GMT$//'
		)

		now="$(date +%s)"
		# GNU date required
		exp="$(date -u -d "$exp_epoch GMT" +%s)"

		echo $(( (exp - now) / 86400 ))
	)"

	eval "${prefix}_STATUS=OK"
	eval "${prefix}_SANS=\"\$san_list\""
	eval "${prefix}_SUBJECT=\"\$subject\""
	eval "${prefix}_ISSUER=\"\$issuer\""
	eval "${prefix}_EXPIRY=\"\$expiry\""
	eval "${prefix}_DAYS=\"\$days_remaining\""
	eval "${prefix}_FP=\"\$fingerprint\""

	echo "✅ $prefix certificate valid (> ${RENEW_MARGIN_DAYS} days remaining)"

	return 0
}

# ------------------------------------------------------------------
# ACME bootstrap
# ------------------------------------------------------------------

"$ACME_HOME/acme.sh" \
	--set-default-ca \
	--server letsencrypt \
	--home "$ACME_HOME"

# ------------------------------------------------------------------
# ECC
# ------------------------------------------------------------------

if ! validate_cert "$ECC_CERT" "$ECC_KEY" ecc ECC; then
	echo "🚀 issuing ECC certificate"

	"$ACME_HOME/acme.sh" \
		--issue \
		--server letsencrypt \
		--dns dns_infomaniak \
		--home "$ACME_HOME" \
		-d "$PRIMARY_DOMAIN" \
		-d "*.$PRIMARY_DOMAIN" \
		-d "*.lan.$PRIMARY_DOMAIN"

	echo "🔍 re-validating ECC certificate"
	validate_cert "$ECC_CERT" "$ECC_KEY" ecc ECC;
fi

# ------------------------------------------------------------------
# RSA
# ------------------------------------------------------------------

if ! validate_cert "$RSA_CERT" "$RSA_KEY" rsa RSA; then
	echo "🚀 issuing RSA certificate"

	"$ACME_HOME/acme.sh" \
		--issue \
		--server letsencrypt \
		--dns dns_infomaniak \
		--home "$ACME_HOME" \
		--keylength 4096 \
		-d "$PRIMARY_DOMAIN" \
		-d "*.$PRIMARY_DOMAIN" \
		-d "*.lan.$PRIMARY_DOMAIN"

	echo "🔍 re-validating RSA certificate"
	validate_cert "$RSA_CERT" "$RSA_KEY" rsa RSA;
fi

echo "│"
printf '│ ECC %-3s expires in %3s days  (renew below %s)  %s\n' \
    "${ECC_STATUS:-FAIL}" \
    "${ECC_DAYS:-0}" \
    "${RENEW_MARGIN_DAYS}" \
    "${ECC_EXPIRY:-N/A}"

printf '│ RSA %-3s expires in %3s days  (renew below %s)  %s\n' \
    "${RSA_STATUS:-FAIL}" \
    "${RSA_DAYS:-0}" \
    "${RENEW_MARGIN_DAYS}" \
    "${RSA_EXPIRY:-N/A}"
echo "│"
echo "│ ECC issuer      ${ECC_ISSUER:-N/A}, ECC subject ${ECC_SUBJECT:-N/A}"
echo "│ ECC SANs        ${ECC_SANS:-N/A}"
echo "│ ECC fingerprint ${ECC_FP:-N/A}"
echo "│"
echo "│ RSA issuer      ${RSA_ISSUER:-N/A}, RSA subject ${RSA_SUBJECT:-N/A}"
echo "│ RSA SANs        ${RSA_SANS:-N/A}"
echo "│ RSA fingerprint ${RSA_FP:-N/A}"

echo "│"
echo "✅ ACME validation complete"