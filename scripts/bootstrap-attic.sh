#!/bin/sh
#bootstrap-attic.sh
# Bootstrap Attic server: build, install, configure, and register systemd unit.
# Intended to be invoked by Make as root.
set -eu

ATTIC_ROOT="${ATTIC_ROOT:-/volume1/homelab/attic}"

: "${SRC_ATTIC_CONFIG:?SRC_ATTIC_CONFIG not set}"
: "${SRC_ATTIC_SERVICE:?SRC_ATTIC_SERVICE not set}"
: "${ATTIC_REF:?ATTIC_REF not set (e.g. v0.1.0 or commit hash)}"

DST_ATTIC_CONFIG="${ATTIC_ROOT}/config.toml"
DST_ATTIC_SERVICE="/etc/systemd/system/attic.service"

ATTIC_REPO="https://github.com/zhaofengli/attic.git"
ATTIC_SRC="/usr/local/src/attic"
ATTIC_SERVER_BIN="/usr/local/bin/atticd"

SECRET_FILE="/etc/attic/jwt-hs256-secret"

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: This script must be run as root"
	exit 1
fi

# ------------------------------------------------------------
# Verify required tools
# ------------------------------------------------------------
for tool in openssl git cargo systemctl; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "   • ERROR: Required tool '$tool' not found"
		exit 1
	fi
done

if [ ! -f "$SECRET_FILE" ]; then
	echo "   • Generating Attic JWT secret"
	install -d -o root -g root -m 0700 /etc/attic
	openssl rand -base64 32 > "$SECRET_FILE"
	chmod 0600 "$SECRET_FILE"
fi

echo "→ Bootstrapping Attic"

# ------------------------------------------------------------
# Ensure Attic runtime directories exist
# ------------------------------------------------------------
echo "   • Ensuring Attic runtime directories exist"
install -d -o root -g root -m 0755 \
	"${ATTIC_ROOT}" \
	"${ATTIC_ROOT}/logs" \
	"${ATTIC_ROOT}/store" \
	"${ATTIC_ROOT}/index"

# ------------------------------------------------------------
# Ensure Attic source checkout exists
# ------------------------------------------------------------
echo "   • Ensuring Attic source checkout"

if [ ! -d "${ATTIC_SRC}/.git" ]; then
	echo "   • Cloning Attic source"
	mkdir -p "$(dirname "${ATTIC_SRC}")"
	git clone "${ATTIC_REPO}" "${ATTIC_SRC}"
fi

echo "   • Checking out Attic revision ${ATTIC_REF}"
cd "${ATTIC_SRC}"
git fetch --tags
git -c advice.detachedHead=false checkout "${ATTIC_REF}"

# ------------------------------------------------------------
# Build and install atticd
# ------------------------------------------------------------
echo "   • Building atticd from source"

cd "${ATTIC_SRC}"
git rev-parse --short HEAD >/dev/null 2>&1 || {
	echo "   • ERROR: Unable to read Attic git revision in ${ATTIC_SRC}"
	exit 1
}
git rev-parse --short HEAD | sed 's/^/   • Using Attic revision: /'

# ------------------------------------------------------------
# Verify Rust toolchain availability
# ------------------------------------------------------------
if ! command -v cargo >/dev/null 2>&1; then
	echo "   • ERROR: Rust toolchain (cargo) not found"
	echo "     Install Rust before running this bootstrap"
	exit 1
fi

# Build only the Attic server binary.
# The client is intentionally excluded: it is not required to run the server
# and currently pulls in a Nix-based build dependency that breaks on Debian.
cargo build --release -p attic-server

if [ ! -x "target/release/atticd" ]; then
	echo "   • ERROR: atticd build failed"
	exit 1
fi

echo "   • Installing atticd"
install -o root -g root -m 0755 "target/release/atticd" "${ATTIC_SERVER_BIN}.new"
mv -f "${ATTIC_SERVER_BIN}.new" "${ATTIC_SERVER_BIN}"

# ------------------------------------------------------------
# Deploy configuration
# ------------------------------------------------------------
if [ -f "${SRC_ATTIC_CONFIG}" ]; then
	echo "   • Deploying config.toml"
	install -o root -g root -m 0644 "${SRC_ATTIC_CONFIG}" "${DST_ATTIC_CONFIG}"
else
	echo "   • WARNING: config.toml missing in repo"
fi
SECRET="$(cat "$SECRET_FILE")"

if [ -f "$DST_ATTIC_CONFIG" ] && \
   ! grep -q '^token-hs256-secret-base64' "$DST_ATTIC_CONFIG"; then
	echo "   • Injecting Attic JWT signing configuration"
	cat >> "$DST_ATTIC_CONFIG" <<EOF

# Injected at install time — do not commit
[jwt.signing]
token-hs256-secret-base64 = "$SECRET"
EOF
fi

# ------------------------------------------------------------
# Install systemd service
# ------------------------------------------------------------
if [ -f "${SRC_ATTIC_SERVICE}" ]; then
	echo "   • Installing systemd service"
	install -D -m 0644 "${SRC_ATTIC_SERVICE}" "${DST_ATTIC_SERVICE}"
	systemctl daemon-reload
	systemctl is-enabled attic >/dev/null 2>&1 || systemctl enable attic
else
	echo "   • WARNING: attic.service missing in repo"
fi

echo "→ Attic bootstrap complete"
