#!/usr/bin/env bash
set -euo pipefail

KEY_ID="${1:-}"
if [ -z "${KEY_ID}" ]; then
  echo "Usage: $0 <GPG_KEY_ID>"
  echo "Example: $0 3502EDA18DEF01C6"
  exit 1
fi

echo "[gpg-bootstrap] Using key ID: ${KEY_ID}"

mkdir -p "${HOME}/.gnupg"
chmod 700 "${HOME}/.gnupg"

echo "[gpg-bootstrap] Checking for existing secret key..."
if gpg --list-secret-keys "${KEY_ID}" >/dev/null 2>&1; then
  SECRET_PRESENT=1
  echo "[gpg-bootstrap]   [✔️] Secret key present"
else
  SECRET_PRESENT=0
  echo "[gpg-bootstrap]   [❌] Secret key missing"
fi

echo "[gpg-bootstrap] Checking git signing configuration..."
CURRENT_SIGNING_KEY="$(git config --global user.signingkey || true)"
if [ "${CURRENT_SIGNING_KEY}" = "${KEY_ID}" ]; then
  GIT_CONFIGURED=1
  echo "[gpg-bootstrap]   [✔️] Git signing key configured"
else
  GIT_CONFIGURED=0
  echo "[gpg-bootstrap]   [❌] Git signing key not configured"
fi

# Fully provisioned path
if [ "${SECRET_PRESENT}" -eq 1 ] && [ "${GIT_CONFIGURED}" -eq 1 ]; then
  cat <<EOF

[gpg-bootstrap] ============================================================
[gpg-bootstrap] [✔️] WSL2 GPG environment already fully provisioned
[gpg-bootstrap] [✔️] No drift detected
[gpg-bootstrap] [✔️] Secret key is present
[gpg-bootstrap] [✔️] Git is configured for signed commits
[gpg-bootstrap] ============================================================

EOF
  exit 0
fi

echo "[gpg-bootstrap] Configuring git for signed commits..."
git config --global user.signingkey "${KEY_ID}"
git config --global commit.gpgsign true
git config --global gpg.program gpg

cat <<EOF

[gpg-bootstrap] ============================================================
[gpg-bootstrap] Base configuration completed.
[gpg-bootstrap] Manual steps required to finalize provisioning:
[gpg-bootstrap] ============================================================

1) Import your private key:

   nano ~/secret.asc
   gpg --import ~/secret.asc

2) Set trust:

   gpg --edit-key ${KEY_ID} trust quit
   (choose: 5 = ultimate)

3) Test signing:

   echo test | gpg --clearsign

4) Securely delete the temporary key file:

   shred -u ~/secret.asc 2>/dev/null || rm -f ~/secret.asc

[gpg-bootstrap] After completing these steps, rerun this script.
[gpg-bootstrap] It will confirm full provisioning and exit cleanly.
EOF
