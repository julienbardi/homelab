#!/usr/bin/env bash
set -euo pipefail

LOCKFILE="$HOME/.ssh/known_hosts.lock"
KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
HOSTS=(
  "127.0.0.1:2222"
  "10.89.12.1:2222"
  "10.89.12.2:2222"
  "10.89.12.3:2222"
  "10.89.12.4:2222"
)

mkdir -p "$HOME/.ssh"
touch "$KNOWN_HOSTS_FILE"
chmod 700 "$HOME/.ssh"
chmod 644 "$KNOWN_HOSTS_FILE"

exec 9>"$LOCKFILE"
flock -x 9 || exit 1

for hostport in "${HOSTS[@]}"; do
  host="${hostport%:*}"
  port="${hostport#*:}"

  current_key_line=$(ssh-keyscan -p "$port" "$host" 2>/dev/null || true)
  if [[ -z "$current_key_line" ]]; then
    echo "❌ Cannot reach SSH server $host:$port"
    continue
  fi

  stored_fp=$(ssh-keygen -F "[$host]:$port" -f "$KNOWN_HOSTS_FILE" 2>/dev/null | awk '/^|1|/ {getline; print}' | ssh-keygen -lf - || true)
  current_fp=$(echo "$current_key_line" | ssh-keygen -lf -)

  if [[ -z "$stored_fp" ]]; then
    echo "➕ Adding new host key for [$host]:$port: $current_fp"
    echo "$current_key_line" >> "$KNOWN_HOSTS_FILE"
  elif [[ "$stored_fp" != "$current_fp" ]]; then
    echo "⚠️ Host key changed for [$host]:$port"
    echo "    Old fingerprint: $stored_fp"
    echo "    New fingerprint: $current_fp"
    echo "    Updating known_hosts (forced)."
    ssh-keygen -R "[$host]:$port" -f "$KNOWN_HOSTS_FILE"
    echo "$current_key_line" >> "$KNOWN_HOSTS_FILE"
  else
    echo "✔️ Host key for [$host]:$port unchanged and trusted."
  fi
done
