#!/bin/sh
set -eu
LC_ALL=C; export LC_ALL

# Usage: install_url_file_if_changed.sh URL DST OWNER GROUP MODE [EXPECTED_SHA256]
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
    --) # end of flags
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
  echo "Usage: $0 [-q] URL DST OWNER GROUP MODE [EXPECTED_SHA256]" >&2
  exit 2
fi

URL="$1"
DST="$2"
OWNER="$3"
GROUP="$4"
MODE="$5"
EXPECTED_SHA256="${6:-}"

case "$URL" in
  http://*|https://*) ;;
  *) echo "ERROR: URL must be http or https" >&2; exit 1 ;;
esac

# require sha256sum
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: sha256sum not found; install coreutils or equivalent" >&2
  exit 1
fi

# Try to create temp workdir on same filesystem as DST for atomic mv when possible.
TMPDIR="${TMPDIR:-/tmp}"
DESTDIR="$(dirname "$DST")"
if WORKDIR="$(mktemp -d "${DESTDIR}/ifc.XXXXXX" 2>/dev/null)"; then
  :
else
  WORKDIR="$(mktemp -d "${TMPDIR}/ifc.XXXXXX")"
fi
trap 'rm -rf "$WORKDIR"' EXIT

TMPFILE="$WORKDIR/asset"

# verbose diagnostics (enable by setting IFC_VERBOSE=1)
if [ "${IFC_VERBOSE:-0}" != "0" ]; then
  echo "DEBUG: URL='$URL'"
  echo "DEBUG: DST='$DST'"
  echo "DEBUG: OWNER='$OWNER' GROUP='$GROUP' MODE='$MODE'"
  echo "DEBUG: WORKDIR='$WORKDIR' TMPFILE='$TMPFILE'"
fi

# download
if ! curl --fail --location --silent --show-error --output "$TMPFILE" "$URL"; then
  echo "ERROR: download failed for $URL" >&2
  exit 1
fi
chmod +x "$TMPFILE" || true

# compute downloaded file sha256 once
DL_SUM="$(sha256sum "$TMPFILE" | awk '{print $1}')"

if [ "${IFC_VERBOSE:-0}" != "0" ]; then
  echo "DEBUG: DL_SUM=$DL_SUM"
fi

# optional pinned checksum verification of the downloaded asset
if [ -n "$EXPECTED_SHA256" ]; then
  if [ "$DL_SUM" != "$EXPECTED_SHA256" ]; then
    echo "ERROR: downloaded asset sha256 mismatch" >&2
    echo "  expected: $EXPECTED_SHA256" >&2
    echo "  actual:   $DL_SUM" >&2
    exit 1
  fi
fi

# compute effective source hash: sha256(URL + sha256(downloaded_file))
SRC_HASH="$(printf '%s\n%s\n' "$URL" "$DL_SUM" | sha256sum | awk '{print $1}')"

# compute destination effective hash if destination exists
DST_HASH=""
STAMP="${DST}.installed_hash"
if [ -f "$STAMP" ]; then
  # prefer persisted stamp (fast, avoids false negatives from metadata or cross-fs moves)
  DST_HASH="$(cat "$STAMP")"
  if [ "${IFC_VERBOSE:-0}" != "0" ]; then
    echo "DEBUG: using stamp $STAMP -> DST_HASH=$DST_HASH"
  fi
else
  if [ -f "$DST" ]; then
    DST_SUM="$(sha256sum "$DST" | awk '{print $1}')"
    DST_HASH="$(printf '%s\n%s\n' "$URL" "$DST_SUM" | sha256sum | awk '{print $1}')"
    if [ "${IFC_VERBOSE:-0}" != "0" ]; then
      echo "DEBUG: DST_SUM=$DST_SUM"
      echo "DEBUG: DST_HASH=$DST_HASH"
    fi
  fi
fi

# if destination exists and effective hashes match, nothing to do
if [ -n "$DST_HASH" ] && [ "$SRC_HASH" = "$DST_HASH" ]; then
  [ "$QUIET" -eq 1 ] || printf "No change: destination already matches effective source (hash %s)\n" "$SRC_HASH"
  exit 0
fi

# ensure parent dir exists
mkdir -p "$(dirname "$DST")"

# install: move into place (force overwrite)
if ! mv -f "$TMPFILE" "$DST"; then
  echo "ERROR: mv failed" >&2
  exit 1
fi

if ! chmod "$MODE" "$DST"; then
  echo "ERROR: chmod failed" >&2
  exit 1
fi

# try chown; if it fails, attempt with sudo
if ! chown "$OWNER:$GROUP" "$DST" 2>/dev/null; then
  if command -v sudo >/dev/null 2>&1; then
    if ! sudo chown "$OWNER:$GROUP" "$DST"; then
      echo "WARNING: chown with sudo failed; leaving ownership as-is" >&2
    fi
  else
    echo "WARNING: chown failed and sudo not available; leaving ownership as-is" >&2
  fi
fi

# persist effective-hash stamp so future runs can compare quickly
if [ -n "$SRC_HASH" ]; then
  printf '%s\n' "$SRC_HASH" > "${STAMP}.tmp" && mv "${STAMP}.tmp" "$STAMP"
fi

sync || true

[ "$QUIET" -eq 1 ] || echo "🚀 Installed: $DST (effective-hash: $SRC_HASH)"
exit 3
