#!/bin/sh
set -eu
LC_ALL=C; export LC_ALL

# Usage:
#   install_url_file_if_changed.sh [-q] URL DST OWNER GROUP MODE [EXPECTED_SHA256] [TTL_SECONDS]
#
# Exit codes:
#   0 -> no change
#   3 -> file replaced
#   >0 -> error

QUIET=0

# Parse optional flags
while [ $# -gt 0 ]; do
  case "$1" in
	-q|--quiet)
	  QUIET=1
	  shift
	  ;;
	--)
	  shift
	  break
	  ;;
	-*)
	  echo "ERROR: unknown option: $1" >&2
	  exit 2
	  ;;
	*)
	  break
	  ;;
  esac
done

if [ "$#" -lt 5 ]; then
  echo "Usage: $0 [-q] URL DST OWNER GROUP MODE [EXPECTED_SHA256] [TTL_SECONDS]" >&2
  exit 2
fi

URL="$1"
DST="$2"
OWNER="$3"
GROUP="$4"
MODE="$5"
EXPECTED_SHA256="${6:-}"
TTL="${7:-0}"   # NEW: TTL is positional argument 8 (index 7 after flags)

case "$URL" in
  http://*|https://*) ;;
  *) echo "ERROR: URL must be http or https" >&2; exit 1 ;;
esac

# require sha256sum
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: sha256sum not found; install coreutils or equivalent" >&2
  exit 1
fi

TMPDIR="${TMPDIR:-/tmp}"
DESTDIR="$(dirname "$DST")"
OBJ_ROOT="${DESTDIR}/objects"

# Create temp workdir on same filesystem if possible
if WORKDIR="$(mktemp -d "${DESTDIR}/ifc.XXXXXX" 2>/dev/null)"; then
  :
else
  WORKDIR="$(mktemp -d "${TMPDIR}/ifc.XXXXXX")"
fi
trap 'rm -rf "$WORKDIR"' EXIT

TMPFILE="$WORKDIR/asset"

STAMP="${DST}.installed_hash"
DST_HASH=""
DST_OBJ_HASH=""

# Read existing stamp (backward compatible: 1 or 2 lines)
if [ -f "$STAMP" ]; then
  DST_HASH="$(sed -n '1p' "$STAMP" 2>/dev/null || true)"
  DST_OBJ_HASH="$(sed -n '2p' "$STAMP" 2>/dev/null || true)"
fi

# TTL fast path: if we know the object hash and TTL > 0, and object is fresh, reuse it
if [ "$TTL" -gt 0 ] && [ -n "$DST_OBJ_HASH" ]; then
  OBJ="${OBJ_ROOT}/${DST_OBJ_HASH}"
  if [ -f "$OBJ" ]; then
	NOW=$(date +%s)
	MTIME=$(stat -c %Y "$OBJ" 2>/dev/null || echo 0)
	AGE=$(( NOW - MTIME ))
	if [ "$AGE" -lt "$TTL" ]; then
	  mkdir -p "$DESTDIR" "$OBJ_ROOT"
	  if ! ln -f "$OBJ" "$DST" 2>/dev/null; then
		cp -f "$OBJ" "$DST"
	  fi
	  chmod "$MODE" "$DST" || true
	  if ! chown "$OWNER:$GROUP" "$DST" 2>/dev/null; then
		command -v sudo >/dev/null 2>&1 && sudo chown "$OWNER:$GROUP" "$DST" || true
	  fi
	  [ "$QUIET" -eq 1 ] || printf "No change: TTL cache hit for %s (object %s)\n" "$DST" "$DST_OBJ_HASH"
	  exit 0
	fi
  fi
fi

# Download fresh copy
if ! curl --fail --location --silent --show-error --output "$TMPFILE" "$URL"; then
  echo "ERROR: download failed for $URL" >&2
  exit 1
fi
chmod +x "$TMPFILE" || true

# Compute downloaded file sha256 once
DL_SUM="$(sha256sum "$TMPFILE" | awk '{print $1}')"

# Optional pinned checksum verification
if [ -n "$EXPECTED_SHA256" ]; then
  if [ "$DL_SUM" != "$EXPECTED_SHA256" ]; then
	echo "ERROR: downloaded asset sha256 mismatch" >&2
	echo "  expected: $EXPECTED_SHA256" >&2
	echo "  actual:   $DL_SUM" >&2
	exit 1
  fi
fi

# Effective source hash: sha256(URL + sha256(downloaded_file))
SRC_HASH="$(printf '%s\n%s\n' "$URL" "$DL_SUM" | sha256sum | awk '{print $1}')"

# If destination exists and effective hashes match, nothing to do
if [ -n "$DST_HASH" ] && [ "$SRC_HASH" = "$DST_HASH" ]; then
  [ "$QUIET" -eq 1 ] || printf "No change: destination already matches effective source (hash %s)\n" "$SRC_HASH"
  exit 0
fi

# Ensure object store exists
mkdir -p "$DESTDIR" "$OBJ_ROOT"

OBJ="${OBJ_ROOT}/${DL_SUM}"

# Install into object store (dedup by content hash)
if [ ! -f "$OBJ" ]; then
  if ! mv -f "$TMPFILE" "$OBJ"; then
	echo "ERROR: mv to object store failed" >&2
	exit 1
  fi
else
  rm -f "$TMPFILE" || true
fi

# Link object to destination (hard link preferred, fallback to copy)
if ! ln -f "$OBJ" "$DST" 2>/dev/null; then
  if ! cp -f "$OBJ" "$DST"; then
	echo "ERROR: failed to install destination from object store" >&2
	exit 1
  fi
fi

if ! chmod "$MODE" "$DST"; then
  echo "ERROR: chmod failed" >&2
  exit 1
fi

# try chown; if it fails, attempt with sudo
if ! chown "$OWNER:$GROUP" "$DST" 2>/dev/null; then
  command -v sudo >/dev/null 2>&1 && sudo chown "$OWNER:$GROUP" "$DST" || true
fi

# Persist stamp: line1=SRC_HASH, line2=DL_SUM (backward compatible)
printf '%s\n%s\n' "$SRC_HASH" "$DL_SUM" > "${STAMP}.tmp" && mv "${STAMP}.tmp" "$STAMP"

sync || true

[ "$QUIET" -eq 1 ] || echo "🚀 Installed: $DST (effective-hash: $SRC_HASH, object: $DL_SUM)"
exit 3
