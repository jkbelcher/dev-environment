#!/usr/bin/env bash
#
# Brings tmux sessions back after a restart: restores the last tmux-resurrect
# save, then opens one Ghostty window with a tab attached to each session.
#
# tmux/install.sh copies this to ~/.local/bin/tmux-restore-sessions and sets
# up a LaunchAgent that runs it at login.
#
# Usage:
#   restore-sessions.sh               Restore the last save and open a tab for
#                                     each session. Does nothing if tmux
#                                     already has sessions, or nothing is saved.
#   restore-sessions.sh NAME [NAME…]  Skip the restore and open a tab for each
#                                     named session that's already running.
#
# Needs Ghostty 1.3 or later (for AppleScript) and the tmux-resurrect plugin.
# The first run asks for permission to control Ghostty.

set -euo pipefail

# launchd starts this with a bare PATH, so look where Homebrew puts tmux.
if ! command -v tmux >/dev/null 2>&1; then
  PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
fi
if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux isn't installed." >&2
  exit 1
fi

restore_script="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"

# --- Restore tmux sessions ---------------------------------------------------

sessions=()

if (( $# > 0 )); then
  for name in "$@"; do
    if tmux has-session -t "=$name" 2>/dev/null; then
      sessions+=("$name")
    else
      echo "No tmux session named '$name'; skipping it." >&2
    fi
  done
else
  if tmux has-session 2>/dev/null; then
    echo "tmux already has sessions; nothing to restore."
    exit 0
  fi
  if [[ ! -f "$restore_script" ]]; then
    echo "tmux-resurrect isn't installed; run tmux/install.sh." >&2
    exit 1
  fi

  # resurrect keeps its saves in one of these, depending on what existed when
  # it first ran. `last` points at the newest save.
  last_save=""
  for dir in "$HOME/.tmux/resurrect" "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"; do
    if [[ -e "$dir/last" ]]; then
      last_save="$dir/last"
      break
    fi
  done
  if [[ -z "$last_save" ]]; then
    echo "No saved tmux sessions to restore."
    exit 0
  fi

  # Start the server with a placeholder session named 0, which resurrect
  # expects on a fresh server: it reuses it if the save has a session 0 and
  # removes it otherwise.
  tmux new-session -d -s 0
  tmux run-shell "$restore_script"

  while IFS= read -r name; do
    sessions+=("$name")
  done < <(tmux list-sessions -F '#{session_name}' | sort -n)
fi

if (( ${#sessions[@]} == 0 )); then
  echo "No sessions to open."
  exit 0
fi

# --- Open a Ghostty tab for each session -------------------------------------

# If Ghostty isn't running, start it without its usual empty first window.
if ! pgrep -xq ghostty; then
  open -ga Ghostty --args --initial-window=false
fi

# Wait for Ghostty to answer AppleScript.
ready=""
for _ in $(seq 1 30); do
  if osascript -e 'tell application "Ghostty" to get version' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [[ -z "$ready" ]]; then
  echo "Ghostty didn't respond to AppleScript. It needs Ghostty 1.3 or later," >&2
  echo "and permission under System Settings > Privacy & Security > Automation." >&2
  exit 1
fi

# Each tab starts the usual shell and types the attach command into it, so
# detaching later leaves a normal shell behind.
osascript - "${sessions[@]}" <<'APPLESCRIPT'
on run sessionNames
  tell application "Ghostty"
    set win to missing value
    repeat with sessionName in sessionNames
      set cfg to new surface configuration
      set initial input of cfg to "tmux attach-session -t " & quoted form of ("=" & sessionName) & linefeed
      if win is missing value then
        set win to new window with configuration cfg
      else
        new tab in win with configuration cfg
      end if
    end repeat
    activate
  end tell
end run
APPLESCRIPT

echo "Opened ${#sessions[@]} Ghostty tab(s): ${sessions[*]}"
