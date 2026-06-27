#!/bin/sh
# install_github_asset.sh URL DEST SHA256 STAMP TOOL_LABEL
# -----------------------------------------------------------------------------
# Safe, idempotent, and deterministic GitHub asset downloader and installer.
# BusyBox-compatible, preserves strict permission and argument contracts.
# -----------------------------------------------------------------------------
set -eu

URL="$1"
DEST="$2"
SHA256_EXPECTED="$3"
STAMP="$4"
TOOL_LABEL="${5:-$(basename "$DEST")}"

BASENAME="$(basename "$DEST")"

# Ensure target system directories exist cleanly
mkdir -p "$(dirname "$DEST")"
mkdir -p "$(dirname "$STAMP")"

TMP_ASSET=""
WORK=""
LIST_FILE=""
TMP_STAMP=""
TMP_DEST=""

cleanup() {
	set +e
	[ -n "$TMP_ASSET" ] && [ -f "$TMP_ASSET" ] && rm -f "$TMP_ASSET" || true
	[ -n "$LIST_FILE" ] && [ -f "$LIST_FILE" ] && rm -f "$LIST_FILE" || true
	[ -n "$TMP_STAMP" ] && [ -f "$TMP_STAMP" ] && rm -f "$TMP_STAMP" || true
	[ -n "$TMP_DEST" ] && [ -f "$TMP_DEST" ] && rm -f "$TMP_DEST" || true
	[ -n "$WORK" ] && [ -d "$WORK" ] && rm -rf "$WORK" || true
}
trap cleanup EXIT

# ------------------------------------------------------------
# Fast-path skip: stamp + dest verification
# ------------------------------------------------------------
if [ -f "$STAMP" ] && [ -x "$DEST" ]; then
	CURRENT="$(sha256sum "$DEST" | awk '{print $1}')"
	if [ "$CURRENT" = "$SHA256_EXPECTED" ]; then
		echo "⏩ ${TOOL_LABEL} (fast-path: hash+stamp OK): $CURRENT"
		exit 0
	fi
fi

# ------------------------------------------------------------
# Local recovery skip: binary matches hash but stamp is missing
# ------------------------------------------------------------
if [ -x "$DEST" ]; then
	CURRENT="$(sha256sum "$DEST" | awk '{print $1}')"
	if [ "$CURRENT" = "$SHA256_EXPECTED" ]; then
		TMP_STAMP="$(mktemp 2>/dev/null || mktemp -t 'stamp')"
		echo "$SHA256_EXPECTED" > "$TMP_STAMP"
		install -m 0644 "$TMP_STAMP" "$STAMP"
		echo "⏩ ${TOOL_LABEL} (local recovery: binary hash OK, stamp restored): $CURRENT"
		exit 0
	fi
fi

# ------------------------------------------------------------
# Download asset securely to transient file (WAN execution)
# ------------------------------------------------------------
TMP_ASSET="$(mktemp 2>/dev/null || mktemp -t 'asset')"
curl -fsSL \
	--connect-timeout 5 \
	--max-time 30 \
	--retry 3 \
	--retry-delay 1 \
	"$URL" -o "$TMP_ASSET"

# ------------------------------------------------------------
# Verify SHA256 integrity of the downloaded payload
# ------------------------------------------------------------
ACTUAL="$(sha256sum "$TMP_ASSET" | awk '{print $1}')"
if [ "$ACTUAL" != "$SHA256_EXPECTED" ]; then
	echo "ERROR: sha256 mismatch" >&2
	echo "  expected: $SHA256_EXPECTED" >&2
	echo "  actual:   $ACTUAL" >&2
	exit 1
fi

# ------------------------------------------------------------
# Detect asset container type
# ------------------------------------------------------------
case "$URL" in
	*.tar.gz|*.tgz) TYPE="tar" ;;
	*.zip)          TYPE="zip" ;;
	*.deb)          TYPE="deb" ;;
	*)              TYPE="raw" ;;
esac

# ------------------------------------------------------------
# Handle raw binary installation directly via atomic transaction
# ------------------------------------------------------------
if [ "$TYPE" = "raw" ]; then
	TMP_DEST="$(mktemp "$(dirname "$DEST")/tmp.XXXXXX" 2>/dev/null || mktemp -t 'dest')"
	install -m 0755 "$TMP_ASSET" "$TMP_DEST"
	mv -f "$TMP_DEST" "$DEST"

	TMP_STAMP="$(mktemp 2>/dev/null || mktemp -t 'stamp')"
	echo "$SHA256_EXPECTED" > "$TMP_STAMP"
	install -m 0644 "$TMP_STAMP" "$STAMP"

	echo "🚀 Installed raw binary: $DEST"
	exit 0
fi

# ------------------------------------------------------------
# Extract archive into isolated temporary workspace
# ------------------------------------------------------------
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t 'work')"

if [ "$TYPE" = "tar" ]; then
	tar -xzf "$TMP_ASSET" -C "$WORK"
elif [ "$TYPE" = "zip" ]; then
	unzip -q "$TMP_ASSET" -d "$WORK"
elif [ "$TYPE" = "deb" ]; then
	dpkg-deb -x "$TMP_ASSET" "$WORK" >/dev/null
fi

# ------------------------------------------------------------
# Strict binary discovery (BusyBox-compliant, space-safe, parent shell)
# ------------------------------------------------------------
MATCHES=""
COUNT=0

LIST_FILE="$(mktemp 2>/dev/null || mktemp -t 'list')"

# Pure POSIX expression to isolate files matching name while filtering metadata.
# Omits non-standard extensions to guarantee execution in minimal environments.
find "$WORK" -type f -name "$BASENAME" 2>/dev/null > "$LIST_FILE"

# Using file redirection (<) to execute the while loop natively within the
# parent process frame, enabling precise tracking of the counter variables.
while IFS= read -r FILE; do
	[ -z "$FILE" ] && continue

	# Isolate and skip macOS indexing overhead and hidden dotfiles safely
	case "$FILE" in
		*__MACOSX*|*/.*) continue ;;
	esac

	MATCHES="$FILE"
	COUNT=$((COUNT + 1))
done < "$LIST_FILE"

if [ "$COUNT" -eq 0 ]; then
	echo "ERROR: no file named '$BASENAME' found in asset" >&2
	exit 1
fi

if [ "$COUNT" -gt 1 ]; then
	echo "ERROR: multiple entries named '$BASENAME' found in asset" >&2
	exit 1
fi

# ------------------------------------------------------------
# Install discovered binary safely via transactional move
# ------------------------------------------------------------
# Staged on the target volume directory to ensure an instantaneous rename operation.
TMP_DEST="$(mktemp "$(dirname "$DEST")/tmp.XXXXXX" 2>/dev/null \
	|| mktemp -p "$(dirname "$DEST")" tmp.XXXXXX)"

install -m 0755 "$MATCHES" "$TMP_DEST"
mv -f "$TMP_DEST" "$DEST"

# ------------------------------------------------------------
# Atomic write of synchronization stamp via transaction move
# ------------------------------------------------------------
TMP_STAMP="$(mktemp 2>/dev/null || mktemp -t 'stamp')"
echo "$SHA256_EXPECTED" > "$TMP_STAMP"
install -m 0644 "$TMP_STAMP" "$STAMP"

echo "🚀 Installed/updated $DEST"