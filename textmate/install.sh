#!/usr/bin/env bash
#
# Installs TextMate with Homebrew (unless it's already in /Applications or
# ~/Applications) and makes it the default text editor:
#
#   - Text and code files (the extensions in file_types below) open in
#     TextMate from Finder. extension_defaults.js saves these settings (its
#     header says why duti can't), then Launch Services is restarted to load
#     them.
#   - The `mate` command is linked into Homebrew's bin directory if it isn't
#     installed already.
#   - EDITOR and VISUAL are set to `mate -w` in ~/.zshrc, so git and other
#     command-line tools open files in TextMate and wait until you close them.
#     If your zsh config already sets EDITOR or VISUAL, it's left alone.
#
# Safe to run again.

set -euo pipefail

# Extensions to open in TextMate. Each one sets the default app for its whole
# file type, so .yml also covers .yaml, and .js also covers .mjs. .ts is also
# MPEG-2 video to macOS, so those videos will open in TextMate too.
#
# Extensions macOS has no file type for (.fish and .go, for example) only
# cover themselves. If an app you install later adds a file type for one of
# them (Xcode does for .toml and .tsx), run this again to point that type at
# TextMate.
#
# Left out on purpose, so they keep opening in their usual app: .md, .html,
# .csv, .log, .plist, and Xcode's languages (.swift, .c, .h, .m). Add any of
# them here if you want TextMate for those too.
file_types=(
  .txt
  .sh .bash .zsh .fish
  .py .rb .pl .php .lua
  .js .cjs .jsx .ts .tsx .css .scss .sass .less
  .json .jsonc .xml .yml .toml .ini .conf .env .properties
  .sql .go .rs .diff
)

editor_cmd="mate -w"

script_dir="$(cd "$(dirname "$0")" && pwd)"

# --- Homebrew ----------------------------------------------------------------

# On a new machine Homebrew may be installed but not on PATH yet.
brew_bin="$(command -v brew || true)"
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -z "$brew_bin" && -x "$candidate" ]]; then
    brew_bin="$candidate"
  fi
done

if [[ -z "$brew_bin" ]]; then
  echo "Homebrew is needed to install TextMate. Install it from" >&2
  echo "https://brew.sh, then run this again." >&2
  exit 1
fi
brew_bin_dir="$(dirname "$brew_bin")"

# --- App ---------------------------------------------------------------------

find_app() {
  for app in "/Applications/TextMate.app" "$HOME/Applications/TextMate.app"; do
    if [[ -d "$app" ]]; then
      echo "$app"
      return
    fi
  done
}

app="$(find_app)"
if [[ -n "$app" ]]; then
  echo "TextMate is already installed at $app"
else
  echo "Installing TextMate with Homebrew..."
  "$brew_bin" install --cask textmate
  app="$(find_app)"
  if [[ -z "$app" ]]; then
    echo "Homebrew finished, but TextMate.app isn't in /Applications or ~/Applications." >&2
    exit 1
  fi
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"

# --- mate command ------------------------------------------------------------

# The Homebrew cask links `mate` into Homebrew's bin directory. Do the same if
# TextMate was installed some other way.
mate_bin="$(command -v mate || true)"
if [[ -z "$mate_bin" && -x "$brew_bin_dir/mate" ]]; then
  mate_bin="$brew_bin_dir/mate"
fi

if [[ -n "$mate_bin" ]]; then
  echo "The mate command is already installed at $mate_bin"
else
  ln -sf "$app/Contents/MacOS/mate" "$brew_bin_dir/mate"
  echo "Linked the mate command into $brew_bin_dir"
fi

# --- Default app for text files ----------------------------------------------

# Make sure Launch Services knows about the app before pointing files at it.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ -x "$lsregister" ]]; then
  "$lsregister" -f "$app"
fi

extension_defaults=("osascript" "-l" "JavaScript" "$script_dir/extension_defaults.js")

# Prints the extensions whose files don't open in TextMate, asking Launch
# Services rather than trusting that saving worked. Prints all of them if it
# can't tell.
not_in_textmate() {
  local out
  if out="$("${extension_defaults[@]}" check "$bundle_id" "${file_types[@]}")"; then
    printf '%s' "$out"
  else
    printf '%s\n' "${file_types[@]}"
  fi
}

# If saving fails, the check lists what wasn't set.
"${extension_defaults[@]}" set "$bundle_id" "${file_types[@]}" || true

not_set="$(not_in_textmate)"
if [[ -n "$not_set" ]]; then
  # Launch Services reads the saved settings only when it starts. launchd
  # starts it again as soon as an app needs it.
  killall -u "$(id -un)" lsd || true
  sleep 1
  not_set="$(not_in_textmate)"
fi

failed=()
while IFS= read -r type; do
  if [[ -n "$type" ]]; then
    failed+=("$type")
  fi
done <<< "$not_set"

if (( ${#failed[@]} == 0 )); then
  echo "TextMate now opens these file types: ${file_types[*]}"
else
  echo "Couldn't make TextMate the default app for: ${failed[*]}" >&2
  echo "Run this again. If they still don't change, set them in Finder: select" >&2
  echo "a file, then File > Get Info > Open with > TextMate > Change All." >&2
fi

# --- EDITOR ------------------------------------------------------------------

zsh_dir="${ZDOTDIR:-$HOME}"
zshrc="$zsh_dir/.zshrc"
editor_changed=false

existing="$(grep -HnE '^[[:space:]]*(export[[:space:]]+)?(EDITOR|VISUAL)=' \
  "$zsh_dir/.zshenv" "$zsh_dir/.zprofile" "$zshrc" "$zsh_dir/.zlogin" \
  2>/dev/null || true)"

if [[ -z "$existing" ]]; then
  {
    echo
    echo "# Use TextMate as the command-line editor (added by dev-env/textmate/install.sh)"
    echo "export EDITOR=\"$editor_cmd\""
    echo "export VISUAL=\"\$EDITOR\""
  } >> "$zshrc"
  editor_changed=true
  echo "Set EDITOR and VISUAL to \"$editor_cmd\" in $zshrc"
elif grep -qE 'EDITOR=.*mate' <<< "$existing"; then
  echo "EDITOR is already set to TextMate in your zsh config"
else
  echo "Your zsh config already sets an editor, so it was left alone:"
  sed 's/^/  /' <<< "$existing"
  echo "To use TextMate instead, change it to: export EDITOR=\"$editor_cmd\""
fi

# git's core.editor setting wins over EDITOR.
if command -v git >/dev/null 2>&1; then
  git_editor="$(git config --global core.editor || true)"
  if [[ -n "$git_editor" && "$git_editor" != *mate* ]]; then
    echo "Note: git is set to use $git_editor (core.editor), not EDITOR."
    echo "To use TextMate for git too: git config --global --unset core.editor"
  fi
fi

echo
if (( ${#failed[@]} > 0 )); then
  echo "Finished, but some file types weren't set (see above)." >&2
  exit 1
elif [[ "$editor_changed" == true ]]; then
  echo "Done. Open a new terminal window (or run: source $zshrc) to pick up EDITOR."
else
  echo "Done."
fi
