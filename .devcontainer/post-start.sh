#!/usr/bin/env bash
set -euo pipefail

echo "--- Running post-start script ---"

# Ensure nix-daemon is up every start/restart
if [ -x "/usr/local/share/nix-entrypoint.sh" ]; then
  sudo /usr/local/share/nix-entrypoint.sh || true
fi

# Make nix binaries available (and user profile tools like jq)
if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
export PATH="$HOME/.nix-profile/bin:$PATH"

# Remove credsStore from Docker config if present
CONFIG_FILE="$HOME/.docker/config.json"
TEMP_CONFIG_FILE="${CONFIG_FILE}.tmp"

if command -v jq >/dev/null 2>&1; then
  if [ -f "$CONFIG_FILE" ]; then
    echo "Checking $CONFIG_FILE for 'credsStore'..."
    if jq -e '.credsStore' "$CONFIG_FILE" >/dev/null; then
      echo "Found 'credsStore'. Removing..."
      if jq 'del(.credsStore)' "$CONFIG_FILE" >"$TEMP_CONFIG_FILE"; then
        mv "$TEMP_CONFIG_FILE" "$CONFIG_FILE"
        echo "Removed 'credsStore' from $CONFIG_FILE."
      else
        echo "ERROR: jq failed to modify $CONFIG_FILE."
        rm -f "$TEMP_CONFIG_FILE"
      fi
    else
      echo "'credsStore' not found. No changes needed."
    fi
  else
    echo "Docker config not found at $CONFIG_FILE. Skipping."
  fi
else
  echo "WARN: jq not found; skipping Docker credsStore cleanup."
fi

echo "--- Post-start script finished ---"
