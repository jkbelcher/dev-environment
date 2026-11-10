#!/usr/bin/env bash
#
# Installs the git shortcuts in aliases.zsh next to this script (shell aliases
# like gs for `git status`):
#
#   - Copies aliases.zsh to ~/.config/zsh/git-aliases.zsh. If a different
#     file is already there, it's moved aside to git-aliases.zsh.bak.<timestamp>
#     first, so nothing is lost.
#   - Adds a line to ~/.zshrc that loads it, unless your zsh config already
#     loads it.
#   - Lists any of the same aliases defined elsewhere in your zsh config, so
#     you can delete them and keep the repo copy as the only one.
#
# To change the shortcuts, edit aliases.zsh and run this again. Needs nothing
# installed first. Safe to run again.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source_file="$script_dir/aliases.zsh"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
dest_file="$config_dir/git-aliases.zsh"
zsh_dir="${ZDOTDIR:-$HOME}"
zshrc="$zsh_dir/.zshrc"
zsh_files=("$zsh_dir/.zshenv" "$zsh_dir/.zprofile" "$zshrc" "$zsh_dir/.zlogin")
changed=false

# --- Aliases file ------------------------------------------------------------

mkdir -p "$config_dir"

if [[ -f "$dest_file" ]] && cmp -s "$source_file" "$dest_file"; then
  echo "Aliases are already up to date at $dest_file"
else
  if [[ -e "$dest_file" || -L "$dest_file" ]]; then
    backup="$dest_file.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$dest_file" "$backup"
    echo "Moved the existing aliases file to $backup"
  fi
  cp "$source_file" "$dest_file"
  changed=true
  echo "Installed aliases to $dest_file"
fi

# --- Load from ~/.zshrc ------------------------------------------------------

# Write the path with $HOME rather than the expanded home directory.
load_path="${dest_file/#"$HOME"/\$HOME}"
load_line="if [[ -f \"$load_path\" ]]; then source \"$load_path\"; fi"

if grep -qF "$(basename "$dest_file")" "${zsh_files[@]}" 2>/dev/null; then
  echo "Your zsh config already loads the aliases"
else
  {
    echo
    echo "# Git shortcuts (added by dev-env/git/install.sh)"
    echo "$load_line"
  } >> "$zshrc"
  changed=true
  echo "Added a line to $zshrc that loads the aliases"
fi

# --- Same aliases defined elsewhere ------------------------------------------

names="$(sed -nE 's/^[[:space:]]*alias[[:space:]]+([A-Za-z0-9_-]+)=.*/\1/p' "$source_file" | paste -sd '|' -)"
dupes="$(grep -HnE "^[[:space:]]*alias[[:space:]]+($names)=" "${zsh_files[@]}" 2>/dev/null || true)"

if [[ -n "$dupes" ]]; then
  echo
  echo "Your zsh config also defines some of these aliases:"
  sed 's/^/  /' <<< "$dupes"
  echo "Delete those lines so the shortcuts come only from $dest_file."
  echo "Until then, whichever definition zsh loads last wins."
fi

echo
if [[ "$changed" == true ]]; then
  echo "Done. Open a new terminal window (or run: source $zshrc) to use the shortcuts."
else
  echo "Done."
fi
