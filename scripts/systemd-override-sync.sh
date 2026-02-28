#!/usr/bin/env bash
# --------------------------------------------------------------------
# systemd-override-sync.sh
# --------------------------------------------------------------------
# CONTRACT:
# - argv[1]: path to freshly generated override (.new)
# - argv[2]: destination override path
# - Must be run as root
# - Idempotent: only updates when content differs
# - Removes .new file in all cases
# - Reloads systemd daemon only on change
# --------------------------------------------------------------------

set -euo pipefail

src_new="${1:?missing source .new file}"
dst="${2:?missing destination file}"

if ! cmp -s "$src_new" "$dst" 2>/dev/null; then
    echo "ğŸ› ï¸ Updating systemd override"
    install -m 644 "$src_new" "$dst"
    rm -f "$src_new"
    systemctl daemon-reload
else
    rm -f "$src_new"
    echo "ğŸ› ï¸ systemd override unchanged"
fi
