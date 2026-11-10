#!/usr/bin/env bash
#
# Sets up a new Mac by running this repo's setup scripts, in this order:
#
#   macos/setup.sh        macOS settings (desktop, Dock, Finder, trackpad)
#   textmate/install.sh   TextMate as the default editor
#   ghostty/install.sh    Ghostty and its config
#   tmux/install.sh       tmux and its config
#
# The Bambu items (bambu-default-infill/ and fusion-to-bambu/) are left out on
# purpose; set those up by hand as the README describes.
#
# Homebrew has to be installed first (https://brew.sh), since the TextMate,
# Ghostty, and tmux scripts install with it. If one script fails, the rest
# still run, and the failures are listed at the end. Safe to run again.

set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"

steps=(
  macos/setup.sh
  textmate/install.sh
  ghostty/install.sh
  tmux/install.sh
)

# --- Homebrew ----------------------------------------------------------------

# Check before changing anything, so a missing Homebrew doesn't leave the
# setup half done. On a new machine it may be installed but not on PATH yet;
# the scripts look in the same places.
brew_bin="$(command -v brew || true)"
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -z "$brew_bin" && -x "$candidate" ]]; then
    brew_bin="$candidate"
  fi
done

if [[ -z "$brew_bin" ]]; then
  echo "Homebrew is needed to install TextMate, Ghostty, and tmux." >&2
  echo "Install it from https://brew.sh, then run this again." >&2
  exit 1
fi

# --- Run the scripts ---------------------------------------------------------

failed=()
for step in "${steps[@]}"; do
  echo
  echo "==> $step"
  if ! bash "$repo_dir/$step"; then
    failed+=("$step")
  fi
done

# --- Summary -----------------------------------------------------------------

echo
if (( ${#failed[@]} > 0 )); then
  echo "These scripts failed (see their output above): ${failed[*]}" >&2
  echo "Fix the problem, then run this again or run just those scripts." >&2
  exit 1
fi

echo "All done. Scroll up for anything the scripts asked you to do next,"
echo "like logging out and back in for the trackpad settings."
