#!/usr/bin/env bash

# Exit immediately if a command fails, if an undefined variable is used,
# or if a pipe fails.
set -euo pipefail

# --- Configuration ---
# Path to your GPG Key ID config file
CONFIG_PATH="${HOME}/config/homelab/gpg-keyid"

# Colors for professional feedback
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# --- Functions ---
usage() {
    echo -e "Usage: sign <file_to_sign>"
    echo ""
    echo "Examples:"
    echo "  sign my_file.txt"
    echo ""
    echo "Note: If you are trying to sign Git commits, you can automate"
    echo "this natively by running:"
    echo "  git config --global user.signingkey YOUR_KEY_ID"
    echo "  git config --global commit.gpgsign true"
    exit 1
}

error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# --- Validation ---

# Check if gpg is installed
if ! command -v gpg &> /dev/null; then
    error_exit "gpg is not installed. Please install it first."
fi

# Check if argument is provided
if [[ $# -eq 0 ]]; then
    echo -e "No file provided."
    usage
fi

# Check if file exists
if [[ ! -f "$1" ]]; then
    error_exit "File '$1' does not exist."
fi

# Check if config file exists and read KEYID
if [[ ! -f "$CONFIG_PATH" ]]; then
    error_exit "Config file missing at $CONFIG_PATH"
fi

KEYID=$(cat "$CONFIG_PATH")
if [[ -z "$KEYID" ]]; then
    error_exit "KEYID in $CONFIG_PATH is empty."
fi

# --- Execution ---

echo "Signing $(basename "$1") with key $KEYID..."

if gpg --batch --yes --pinentry-mode loopback \
    --local-user "$KEYID" \
    --detach-sign "$1" > /dev/null 2>&1; then
    echo -e "${GREEN}Successfully signed $(basename "$1")${NC}"
else
    error_exit "GPG signing failed."
fi
