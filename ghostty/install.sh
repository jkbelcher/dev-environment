#!/usr/bin/env bash
#
# Installs Ghostty with Homebrew (unless it's already in /Applications or
# ~/Applications), then copies the config next to this script to
# ~/.config/ghostty/config.
#
# If a different config is already there, it's moved aside to
# config.bak.<timestamp> first, so nothing is lost. Safe to run again.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source_config="$script_dir/config"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
dest_config="$config_dir/config"

# --- App ---------------------------------------------------------------------

installed_app=""
for app in "/Applications/Ghostty.app" "$HOME/Applications/Ghostty.app"; do
  if [[ -d "$app" ]]; then
    installed_app="$app"
    break
  fi
done

if [[ -n "$installed_app" ]]; then
  echo "Ghostty is already installed at $installed_app"
else
  # On a new machine Homebrew may be installed but not on PATH yet.
  brew_bin="$(command -v brew || true)"
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -z "$brew_bin" && -x "$candidate" ]]; then
      brew_bin="$candidate"
    fi
  done

  if [[ -z "$brew_bin" ]]; then
    echo "Homebrew is needed to install Ghostty. Install it from https://brew.sh" >&2
    echo "(or download Ghostty from https://ghostty.org/download), then run this again." >&2
    exit 1
  fi

  echo "Installing Ghostty with Homebrew..."
  "$brew_bin" install --cask ghostty
fi

# --- Config ------------------------------------------------------------------

mkdir -p "$config_dir"

if [[ -f "$dest_config" ]] && cmp -s "$source_config" "$dest_config"; then
  echo "Config is already up to date at $dest_config"
else
  if [[ -e "$dest_config" || -L "$dest_config" ]]; then
    backup="$dest_config.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$dest_config" "$backup"
    echo "Moved the existing config to $backup"
  fi
  cp "$source_config" "$dest_config"
  echo "Installed config to $dest_config"
fi

# Ghostty also loads these. Anything set in them can override the repo config.
for other in \
  "$config_dir/config.ghostty" \
  "$HOME/Library/Application Support/com.mitchellh.ghostty/config" \
  "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
  if [[ -s "$other" ]]; then
    echo "Note: Ghostty also reads $other, which can override these settings."
  fi
done

echo
echo "Done. If Ghostty is running, reload the config with Cmd+Shift+, (or restart it)."
