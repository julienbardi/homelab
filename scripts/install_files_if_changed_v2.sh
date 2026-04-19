#!/bin/bash
# --------------------------------------------------------------------
# scripts/install_files_if_changed_v2.sh
# --------------------------------------------------------------------
# Standalone wrapper for the vectorized IFC engine.
# Usage:
#   install_files_if_changed_v2.sh <var_name> <ifc_args...>
# Arguments are passed in groups of 9, matching install_file_if_changed_v2.sh:
#   "" "" SRC HOST PORT DST OWNER GROUP MODE
# --------------------------------------------------------------------

# 1. Locate and source common.sh
if [ -f "/usr/local/bin/common.sh" ]; then
    # shellcheck disable=SC1091
    source "/usr/local/bin/common.sh"
elif [ -f "$(dirname "$0")/common.sh" ]; then
    # shellcheck disable=SC1091
    source "$(dirname "$0")/common.sh"
else
    echo "❌ Error: common.sh not found." >&2
    exit 1
fi

# 2. Verify the function exists in common.sh
if ! declare -f install_files_if_changed_v2 >/dev/null; then
    echo "❌ Error: Function install_files_if_changed_v2 not defined in common.sh" >&2
    exit 1
fi

# 3. Execution
VAR_NAME=$1
install_files_if_changed_v2 "$@"

# Check if the variable was set to 1 inside the function
if [ "${!VAR_NAME}" -eq 1 ]; then
    exit 3  # Match INSTALL_IF_CHANGED_EXIT_CHANGED
fi

exit 0