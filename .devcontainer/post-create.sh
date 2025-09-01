#!/usr/bin/env bash
set -euo pipefail

echo "--- Post-create: starting ---"

# Ensure nix is usable for this user
if [ -x "/usr/local/share/nix-entrypoint.sh" ]; then
  echo "Starting nix-daemon..."
  sudo /usr/local/share/nix-entrypoint.sh || true
fi

# Make sure nix command is in PATH for this shell
if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
export PATH="$HOME/.nix-profile/bin:$PATH"

# Install dev tools from your flake into the user profile
# Requires flake.nix at repo root with packages.devtools
echo "--- Installing flake packages: .#devtools ---"

cd .devcontainer
nix --accept-flake-config \
  --extra-experimental-features "nix-command flakes" \
  profile install .#devtools || {
  echo "ERROR: nix profile install failed"; exit 1;
}

export ENV="$HOME/.bashrc"
export SHELL="$(which bash)"
export EXPECTED_PNPM_HOME="$HOME/.local/share/pnpm"

cd ..

# Optional: initialize Git LFS for the user
if command -v git-lfs >/dev/null 2>&1; then
  git lfs install --skip-repo || true
fi

# PNPM setup and packages
echo "--- Setting up pnpm ---"
if command -v pnpm >/dev/null 2>&1; then
  pnpm setup || echo "pnpm setup finished (ignoring potential non-zero exit if dir already configured)"

  # Load any changes to PATH that pnpm wrote
  if [ -f "$HOME/.bashrc" ]; then
    # shellcheck disable=SC1090
    . "$HOME/.bashrc"
  fi

  export PNPM_HOME="$EXPECTED_PNPM_HOME"
  export PATH="$PNPM_HOME:$PATH"

  sleep 1

  # Global tools
  pnpm install -g turbo || true

  # Project deps
  if [ -f "package.json" ]; then
    pnpm install || echo "pnpm install finished (ignoring potential non-zero exit if dir already configured)"
  else
    echo "No package.json found, skipping pnpm install."
  fi
else
  echo "WARN: pnpm not found on PATH (should be in devtools)."
fi

# Configure Android SDK env persistently in ~/.bashrc
echo "--- Configuring Android SDK environment ---"
SDKMANAGER_BIN="$(command -v sdkmanager || true)"
if [ -n "$SDKMANAGER_BIN" ]; then
  SDKMANAGER_REAL="$(readlink -f "$SDKMANAGER_BIN")"
  OUT_DIR="$(dirname "$(dirname "$SDKMANAGER_REAL")")"
  CANDIDATE1="$OUT_DIR/libexec/android-sdk"
  CANDIDATE2="$OUT_DIR/share/android-sdk"

  if [ -d "$CANDIDATE1" ]; then
    ANDROID_ROOT="$CANDIDATE1"
  elif [ -d "$CANDIDATE2" ]; then
    ANDROID_ROOT="$CANDIDATE2"
  else
    ANDROID_ROOT=""
  fi

  if [ -n "${ANDROID_ROOT:-}" ]; then
    BLOCK_START="# >>> Android SDK (Nix) >>>"
    BLOCK_END="# <<< Android SDK (Nix) <<<"
    if ! grep -q "$BLOCK_START" "$HOME/.bashrc" 2>/dev/null; then
      {
        echo "$BLOCK_START"
        echo "export ANDROID_SDK_ROOT=\"$ANDROID_ROOT\""
        echo "export ANDROID_HOME=\"\$ANDROID_SDK_ROOT\""
        echo "export PATH=\"\$ANDROID_SDK_ROOT/platform-tools:\$PATH\""
        echo "export PATH=\"\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$PATH\""
        echo "$BLOCK_END"
      } >>"$HOME/.bashrc"
      echo "Wrote ANDROID_* env to ~/.bashrc"
    else
      echo "ANDROID_* block already present in ~/.bashrc"
    fi
  else
    echo "WARN: Could not locate ANDROID_SDK_ROOT under $OUT_DIR"
  fi
else
  echo "WARN: sdkmanager not found (is androidsdk in devtools?)"
fi

# Configure JAVA_HOME persistently in ~/.bashrc
echo "--- Configuring JAVA_HOME ---"
JAVAC_BIN="$(command -v javac || true)"
if [ -n "$JAVAC_BIN" ]; then
  JDK_ROOT="$(dirname "$(dirname "$(readlink -f "$JAVAC_BIN")")")"
  BLOCK_START="# >>> Java (Nix) >>>"
  BLOCK_END="# <<< Java (Nix) <<<"
  if ! grep -q "$BLOCK_START" "$HOME/.bashrc" 2>/dev/null; then
    {
      echo "$BLOCK_START"
      echo "export JAVA_HOME=\"$JDK_ROOT\""
      echo "export PATH=\"\$JAVA_HOME/bin:\$PATH\""
      echo "$BLOCK_END"
    } >>"$HOME/.bashrc"
    echo "Wrote JAVA_HOME to ~/.bashrc"
  else
    echo "JAVA_HOME block already present in ~/.bashrc"
  fi
else
  echo "WARN: javac not found (is jdk in devtools?)"
fi

echo "--- Post-create: done ---"