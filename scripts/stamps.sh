#!/bin/sh
# ============================================================
# Unified stamp library — deterministic, BusyBox-safe
# ============================================================
# Provides:
#   stamp_dir
#   stamp_init
#   stamp_compute_hash
#   stamp_should_skip
#   stamp_update
#
# This file lives in scripts/ (flat), so install-all picks it up.
# ============================================================

set -eu

# ------------------------------------------------------------
# Resolve user-level stamp directory (privilege-correct)
# ------------------------------------------------------------
stamp_dir() {
    if [ -n "${XDG_STATE_HOME:-}" ]; then
        printf '%s/homelab' "$XDG_STATE_HOME"
    else
        printf '%s/.local/state/homelab' "$HOME"
    fi
}

# ------------------------------------------------------------
# Ensure stamp directory exists
# ------------------------------------------------------------
stamp_init() {
    dir="$(stamp_dir)"
    mkdir -p "$dir"
    printf '%s' "$dir"
}

# ------------------------------------------------------------
# Compute deterministic hash of all git-tracked files
# ------------------------------------------------------------
stamp_compute_hash() {
    list="$(stamp_git_filelist)"
    sha256sum "$list" | awk '{print $1}'
}

# ------------------------------------------------------------
# Compute hash of an explicit file list (per-invariant hashing)
# Usage:
#   stamp_compute_hash_files file1 file2 ...
# ------------------------------------------------------------
stamp_compute_hash_files() {
    # BusyBox-safe: no arrays, no xargs -0
    sha256sum "$@" | sha256sum | awk '{print $1}'
}

# ------------------------------------------------------------
# Gitignore invariant hash
# ------------------------------------------------------------
stamp_compute_hash_gitignore() {
    stamp_compute_hash_files \
        "$REPO_ROOT/.gitignore" \
        "$REPO_ROOT/scripts/gitignore-check.sh" \
        "$REPO_ROOT/mk/20_gitignore.mk"
}

# ------------------------------------------------------------
# Check if stamp exists and matches current hash
# Usage:
#   stamp_should_skip <stamp_file>
# Returns:
#   0 = skip
#   1 = run
# ------------------------------------------------------------
stamp_should_skip() {
    stamp_file="$1"
    current="$(stamp_compute_hash)"

    if [ -f "$stamp_file" ]; then
        stored="$(cat "$stamp_file")"
        if [ "$current" = "$stored" ]; then
            return 0
        fi
    fi

    return 1
}

# ------------------------------------------------------------
# Update stamp after successful invariant
# Usage:
#   stamp_update <stamp_file>
# ------------------------------------------------------------
stamp_update() {
    stamp_file="$1"
    stamp_compute_hash > "$stamp_file"
}

# ------------------------------------------------------------
# Cached git file list
# ------------------------------------------------------------
stamp_git_filelist() {
    dir="$(stamp_dir)"
    list="$dir/git-files.txt"
    stamp="$dir/git-files.stamp"

    mkdir -p "$dir"

    compute_list_hash() {
        git ls-files -z | sha256sum | awk '{print $1}'
    }

    current="$(compute_list_hash)"

    if [ -f "$stamp" ]; then
        stored="$(cat "$stamp")"
        if [ "$current" = "$stored" ]; then
            # Cache is valid
            printf '%s' "$list"
            return 0
        fi
    fi

    # Cache is stale → regenerate
    git ls-files > "$list"
    printf '%s\n' "$current" > "$stamp"

    printf '%s' "$list"
}
