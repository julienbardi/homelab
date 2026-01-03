#!/bin/sh
set -eu

# --------------------------------------------------------------------
# NOTE — IMPORTANT DESIGN INTENT
#
# This script intentionally tests *internal reachability* of the
# apt-cacher-ng backend (via its private IP), NOT public accessibility.
#
# Why:
# - apt.bardi.ch:3142 is intentionally NOT exposed publicly
# - Caddy blocks this hostname/port from the internet by design
# - Testing the public hostname here would *always* fail off-LAN
#
# Therefore:
# - The health probe MUST target the internal backend IP
# - The proxy configuration MUST still use the hostname (apt.bardi.ch)
#
# In short:
#   Probe = "Can this client reach the cache internally?"
#   Proxy = "Use apt.bardi.ch when the cache is reachable"
#
# This avoids disabling the proxy on LAN/VPN while preserving
# strict non-public exposure of apt-cacher-ng.
# --------------------------------------------------------------------

BACKEND_URL="http://10.89.12.4:3142/acng-report.html"
PROXY_URL="http://apt.bardi.ch:3142"
CONF_FILE="/etc/apt/apt.conf.d/01proxy"

TMP_FILE="$(mktemp)"
cleanup() { rm -f "$TMP_FILE"; }
trap cleanup EXIT

if curl -fsS --max-time 2 "$BACKEND_URL" >/dev/null; then
	printf 'Acquire::http::Proxy "%s";\n' "$PROXY_URL" >"$TMP_FILE"
	install -m 0644 -o root -g root "$TMP_FILE" "$CONF_FILE"
	echo "apt-proxy-auto: ENABLED ($PROXY_URL)"
else
	rm -f "$CONF_FILE"
	echo "apt-proxy-auto: DISABLED (backend unreachable)"
fi
