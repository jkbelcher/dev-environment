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
#   restore-sessions.sh --on-ghostty-launch
#                                     For the hook tmux/install.sh adds to
#                                     ~/.zshrc. Acts only from a shell in a
#                                     Ghostty that started within the last
#                                     minute, and only if nothing is attached
#                                     to tmux. If tmux is still running, it
#                                     opens a tab for each session; if not, it
#                                     restores the last save first. Exits 0
#                                     only if it opened tabs; the hook then
#                                     closes the shell it ran in, leaving
#                                     just the tabs.
#                                     Output goes to
#                                     ~/Library/Logs/tmux-restore-sessions.log.
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

# --- Ghostty launch hook -----------------------------------------------------

# In this mode every exit except the last one must be non-zero: the zsh hook
# closes its shell on 0, and a wrong 0 would close every new terminal.
on_launch=""
reattach_only=""
if [[ "${1:-}" == "--on-ghostty-launch" ]]; then
  on_launch=1
  shift

  # Only from a Ghostty shell that isn't inside tmux.
  [[ -n "${GHOSTTY_RESOURCES_DIR:-}" && -z "${TMUX:-}" ]] || exit 1

  # If tmux outlived Ghostty, its sessions are all detached and only need
  # tabs. If anything is attached, the tabs are already there.
  if tmux has-session 2>/dev/null; then
    if [[ -n "$(tmux list-clients 2>/dev/null)" ]]; then
      exit 1
    fi
    reattach_only=1
  fi

  # Only when Ghostty has just started. ps prints the age of a process under
  # a minute old as 00:SS.
  # (-a: pgrep leaves out its own ancestors otherwise, and Ghostty is one.)
  ghostty_pid="$(pgrep -anx ghostty || true)"
  [[ -n "$ghostty_pid" ]] || exit 1
  ghostty_age="$(ps -o etime= -p "$ghostty_pid" | tr -d ' ')"
  [[ "$ghostty_age" =~ ^00:[0-5][0-9]$ ]] || exit 1

  # Act once per Ghostty launch. The tabs opened below start shells that run
  # this hook too, before their attach command has run, so without this each
  # one would see detached sessions and open another set of tabs, without
  # end. Two independent checks: a lock named for this Ghostty process, and a
  # stamp that blocks any second run within two minutes.
  state_dir="${TMPDIR:-/tmp}/tmux-restore-sessions"
  mkdir -p "$state_dir"
  if [[ -n "$(find "$state_dir" -name stamp -mmin -2 2>/dev/null)" ]]; then
    exit 1
  fi
  find "$state_dir" -mindepth 1 -maxdepth 1 -name 'ghostty.*' ! -name "ghostty.$ghostty_pid" -exec rmdir {} + 2>/dev/null || true
  mkdir "$state_dir/ghostty.$ghostty_pid" 2>/dev/null || exit 1
  touch "$state_dir/stamp"

  mkdir -p "$HOME/Library/Logs"
  exec >> "$HOME/Library/Logs/tmux-restore-sessions.log" 2>&1
  echo "$(date '+%Y-%m-%d %H:%M:%S') Ghostty started with no tabs attached to tmux"
fi

# Ends a run that had nothing to do.
nothing_to_do() {
  echo "$1"
  if [[ -n "$on_launch" ]]; then
    exit 1
  fi
  exit 0
}

# --- Restore tmux sessions ---------------------------------------------------

sessions=()

list_sessions() {
  while IFS= read -r name; do
    sessions+=("$name")
  done < <(tmux list-sessions -F '#{session_name}' | sort -n)
}

if [[ -n "$reattach_only" ]]; then
  list_sessions
elif (( $# > 0 )); then
  for name in "$@"; do
    if tmux has-session -t "=$name" 2>/dev/null; then
      sessions+=("$name")
    else
      echo "No tmux session named '$name'; skipping it." >&2
    fi
  done
else
  if tmux has-session 2>/dev/null; then
    nothing_to_do "tmux already has sessions; nothing to restore."
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
    nothing_to_do "No saved tmux sessions to restore."
  fi

  # Start the server with a placeholder session named 0, which resurrect
  # expects on a fresh server: it reuses it if the save has a session 0 and
  # removes it otherwise.
  tmux new-session -d -s 0
  tmux run-shell "$restore_script"
  list_sessions
fi

if (( ${#sessions[@]} == 0 )); then
  nothing_to_do "No sessions to open."
fi

# --- Open a Ghostty tab for each session -------------------------------------

# If Ghostty isn't running, start it without its usual empty first window.
if ! pgrep -axq ghostty; then
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
