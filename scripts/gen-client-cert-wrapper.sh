#!/usr/bin/env bash
# scripts/gen-client-cert-wrapper.sh
# Usage: gen-client-cert-wrapper.sh <CN> <run_as_root> <script_dir> [--force]

set -euo pipefail

if [ $# -lt 3 ]; then
	echo "usage: $0 CN RUN_AS_ROOT SCRIPT_DIR [--force]" >&2
	exit 2
fi

CN="$1"
RUN_AS_ROOT="$2"   # e.g. ./bin/run-as-root
SCRIPT_DIR="$3"    # e.g. /path/to/scripts
FORCE_FLAG="${4:-}"  # optional "--force"

CLIENT_DIR="/etc/ssl/caddy/clients"
P12="$CLIENT_DIR/$CN.p12"
CRT="$CLIENT_DIR/$CN.crt"
VERIF_DIR="$CLIENT_DIR/verification"
FINAL_PATH="$VERIF_DIR/$CN-verification.txt"
LOCKFILE="/var/lock/gen-client-cert-$CN.lock"

"$RUN_AS_ROOT" mkdir -p "$VERIF_DIR"
"$RUN_AS_ROOT" chmod 0700 "$VERIF_DIR"

"$RUN_AS_ROOT" "$SCRIPT_DIR/generate-client-cert.sh" "$CN" $FORCE_FLAG

"$RUN_AS_ROOT" touch "$LOCKFILE"
if ! "$RUN_AS_ROOT" flock -n "$LOCKFILE" true 2>/dev/null; then
	echo "[gen-client-cert-wrapper] another gen-client-cert for $CN is running; retrying once..."
	sleep 0.2
	if ! "$RUN_AS_ROOT" flock -n "$LOCKFILE" true 2>/dev/null; then
		echo "[gen-client-cert-wrapper] lock busy, aborting"
		exit 1
	fi
fi

if "$RUN_AS_ROOT" test -f "$CRT"; then
	SUBJECT=$("$RUN_AS_ROOT" openssl x509 -in "$CRT" -noout -subject 2>/dev/null)
	SHA1_RAW=$("$RUN_AS_ROOT" openssl x509 -in "$CRT" -noout -fingerprint -sha1 2>/dev/null)
	SHA256_RAW=$("$RUN_AS_ROOT" openssl x509 -in "$CRT" -noout -fingerprint -sha256 2>/dev/null)
else
	if [ -n "${EXPORT_P12_PASS:-}" ]; then
		CERT=$("$RUN_AS_ROOT" openssl pkcs12 -in "$P12" -clcerts -nokeys -passin env:EXPORT_P12_PASS 2>/dev/null)
		SUBJECT=$(printf "%s" "$CERT" | openssl x509 -noout -subject)
		SHA1_RAW=$(printf "%s" "$CERT" | openssl x509 -noout -fingerprint -sha1)
		SHA256_RAW=$(printf "%s" "$CERT" | openssl x509 -noout -fingerprint -sha256)
	else
		echo "[gen-client-cert-wrapper] warning: certificate PEM not found and EXPORT_P12_PASS not set; cannot compute fingerprints"
		SUBJECT="(certificate PEM not available)"
		SHA1_RAW="(n/a)"
		SHA256_RAW="(n/a)"
	fi
fi

TMP_PATH=$("$RUN_AS_ROOT" mktemp "$VERIF_DIR/$CN-verification.XXXXXX")

printf "%s\n\n%s\n%s\n" "$SUBJECT" "$SHA1_RAW" "$SHA256_RAW" | "$RUN_AS_ROOT" tee "$TMP_PATH" >/dev/null

"$RUN_AS_ROOT" chmod 0600 "$TMP_PATH"
"$RUN_AS_ROOT" chown root:root "$TMP_PATH"
"$RUN_AS_ROOT" mv -f "$TMP_PATH" "$FINAL_PATH"

echo "[gen-client-cert-wrapper] verification file: $FINAL_PATH"
exit 0
