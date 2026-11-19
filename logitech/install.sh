#!/usr/bin/env bash
#
# Installs OpenLogi (https://openlogi.org), a local-first alternative to
# Logitech Options+, with Homebrew, unless it's already in /Applications or
# ~/Applications.
#
# Run this by hand; the top-level install.sh leaves it out on purpose.
# Safe to run again.

set -euo pipefail

# --- App ---------------------------------------------------------------------

installed_app=""
for app in "/Applications/OpenLogi.app" "$HOME/Applications/OpenLogi.app"; do
  if [[ -d "$app" ]]; then
    installed_app="$app"
    break
  fi
done

if [[ -n "$installed_app" ]]; then
  echo "OpenLogi is already installed at $installed_app"
  exit 0
fi

# On a new machine Homebrew may be installed but not on PATH yet.
brew_bin="$(command -v brew || true)"
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -z "$brew_bin" && -x "$candidate" ]]; then
    brew_bin="$candidate"
  fi
done

if [[ -z "$brew_bin" ]]; then
  echo "Homebrew is needed to install OpenLogi. Install it from" >&2
  echo "https://brew.sh, then run this again." >&2
  exit 1
fi

echo "Installing OpenLogi with Homebrew..."
"$brew_bin" install --cask openlogi

echo
echo "Done."
