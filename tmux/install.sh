#!/usr/bin/env bash
#
# Installs tmux with Homebrew (unless it's already on PATH), then copies
# tmux.conf.bak next to this script to ~/.tmux.conf.
#
# If a different ~/.tmux.conf is already there, it's moved aside to
# .tmux.conf.bak.<timestamp> first, so nothing is lost. Safe to run again.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source_config="$script_dir/tmux.conf.bak"
dest_config="$HOME/.tmux.conf"

# --- tmux --------------------------------------------------------------------

# On a new machine Homebrew may be installed but not on PATH yet.
brew_bin="$(command -v brew || true)"
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -z "$brew_bin" && -x "$candidate" ]]; then
    brew_bin="$candidate"
  fi
done

tmux_bin="$(command -v tmux || true)"
if [[ -z "$tmux_bin" && -n "$brew_bin" ]]; then
  brew_tmux="$(dirname "$brew_bin")/tmux"
  [[ -x "$brew_tmux" ]] && tmux_bin="$brew_tmux"
fi

if [[ -n "$tmux_bin" ]]; then
  echo "tmux is already installed at $tmux_bin ($("$tmux_bin" -V))"
else
  if [[ -z "$brew_bin" ]]; then
    echo "Homebrew is needed to install tmux. Install it from https://brew.sh," >&2
    echo "then run this again." >&2
    exit 1
  fi

  echo "Installing tmux with Homebrew..."
  "$brew_bin" install tmux
  tmux_bin="$(dirname "$brew_bin")/tmux"
fi

# --- Config ------------------------------------------------------------------

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

# tmux can load these too. Anything set in them can override the repo config.
others=("$HOME/.config/tmux/tmux.conf" "/etc/tmux.conf")
if [[ -n "${XDG_CONFIG_HOME:-}" && "$XDG_CONFIG_HOME" != "$HOME/.config" ]]; then
  others+=("$XDG_CONFIG_HOME/tmux/tmux.conf")
fi
if [[ -n "$brew_bin" ]]; then
  others+=("$(dirname "$(dirname "$brew_bin")")/etc/tmux.conf")
fi
for other in "${others[@]}"; do
  if [[ -s "$other" ]]; then
    echo "Note: tmux may also read $other, which can override these settings."
  fi
done

echo
if "$tmux_bin" list-sessions >/dev/null 2>&1; then
  echo "Done. tmux is running; reload the config with prefix + r"
  echo "(Ctrl+Space, then r) or: tmux source-file ~/.tmux.conf"
else
  echo "Done. Start tmux with: tmux"
fi
