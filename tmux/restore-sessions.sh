#!/usr/bin/env bash
#
# Brings tmux sessions back after a restart: restores the last tmux-resurrect
# save, then opens a Ghostty tab attached to each session, in the windows the
# tabs were in when they were last recorded.
#
# tmux/install.sh copies this to ~/.local/bin/tmux-restore-sessions, sets up a
# LaunchAgent that runs it at login, and has tmux-resurrect run it with
# --save-windows after every save.
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
#   restore-sessions.sh --save-windows
#                                     Record which Ghostty window and tab each
#                                     attached session is in, for the next
#                                     run that opens tabs. Opens nothing.
#                                     Needs Ghostty 1.4 or later. Without a
#                                     terminal, output goes to the log.
#
# The record is ~/.local/state/tmux-restore-sessions/windows. Tabs come back
# in the same windows, in the same order, with the same tab selected. Sessions
# that had no tab share one more window. Window position and size aren't
# restored, and a tab split into several terminals comes back as a tab for
# each. Without a record, every session goes in one window.
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
log_file="$HOME/Library/Logs/tmux-restore-sessions.log"

# Under $HOME rather than $TMPDIR, so the LaunchAgent, the zsh hook, and tmux
# all see the same files.
state_dir="$HOME/.local/state/tmux-restore-sessions"
windows_file="$state_dir/windows"
stamp="$state_dir/stamp"

# Every run touches the stamp when it starts restoring and again before it
# opens tabs. While the stamp is under two minutes old, tabs may still be on
# their way or not attached yet.
stamp_is_fresh() {
  [[ -n "$(find "$stamp" -mmin -2 2>/dev/null)" ]]
}

now() {
  date '+%Y-%m-%d %H:%M:%S'
}

# --- Save windows ------------------------------------------------------------

# Prints a line for each terminal in Ghostty: window number (1 is the front
# window), tab index, 1 if the tab is selected, and tty, separated by tabs.
# Prints "old VERSION" instead if this Ghostty is too old to report ttys.
list_ghostty_terminals() {
  osascript - <<'APPLESCRIPT'
on run
  -- Inside the tell block, "tab" means a Ghostty tab, not the character.
  set sep to character id 9
  set out to ""
  with timeout of 20 seconds
    tell application "Ghostty"
      considering numeric strings
        if version < "1.4" then return "old " & version
      end considering
      -- Fetch each list before looping over it. That gives references by id.
      -- Looping over "windows" directly goes by position, which changes
      -- whenever another window comes to the front.
      set windowNumber to 0
      set windowList to windows
      repeat with win in windowList
        set windowNumber to windowNumber + 1
        set tabList to tabs of win
        repeat with t in tabList
          set isSelected to 0
          if selected of t then set isSelected to 1
          set tabIndex to index of t
          set terminalList to terminals of t
          repeat with term in terminalList
            set device to ""
            try
              set device to (tty of term) as text
            end try
            set out to out & windowNumber & sep & tabIndex & sep & isSelected & sep & device & linefeed
          end repeat
        end repeat
      end repeat
    end tell
  end timeout
  return out
end run
APPLESCRIPT
}

if [[ "${1:-}" == "--save-windows" ]]; then
  mkdir -p "$state_dir"

  # tmux-resurrect runs this after every save, with no terminal: log only
  # changes and errors there. From a terminal, say what happened.
  quiet=""
  if [[ ! -t 1 ]]; then
    quiet=1
    mkdir -p "$(dirname "$log_file")"
    exec >> "$log_file" 2>&1
  fi
  not_saved() {
    [[ -n "$quiet" ]] || echo "Windows not saved: $1"
    exit 0
  }

  # tmux knows the tty each attached client is on.
  clients="$(tmux list-clients -F '#{client_tty} #{session_name}' 2>/dev/null || true)"
  [[ -n "$clients" ]] || not_saved "no tmux session is attached."
  pgrep -axq ghostty || not_saved "Ghostty isn't running."
  if stamp_is_fresh; then
    not_saved "tabs were opened in the last two minutes and may still be starting. Try again shortly."
  fi

  if ! terminals="$(list_ghostty_terminals 2>&1)"; then
    echo "$(now) Couldn't read Ghostty's windows: $terminals"
    exit 1
  fi
  if [[ "$terminals" == old\ * ]]; then
    not_saved "that needs Ghostty 1.4 or later (this is ${terminals#old })."
  fi

  # Match each terminal's tty to the tmux client on it. For the terminals
  # that have one, keep the window number, the selected flag, and the session
  # name, in window then tab order.
  new_file="$(mktemp "$state_dir/windows.XXXXXX")"
  trap 'rm -f "$new_file"' EXIT
  awk -F '\t' '
    NR == FNR {
      space = index($0, " ")
      session[substr($0, 1, space - 1)] = substr($0, space + 1)
      next
    }
    ($4 in session) { print $1 FS $2 FS $3 FS session[$4] }
  ' <(printf '%s\n' "$clients") <(printf '%s\n' "$terminals") \
    | sort -s -t "$(printf '\t')" -k 1,1n -k 2,2n | cut -f 1,3,4 > "$new_file"

  if [[ ! -s "$new_file" ]]; then
    not_saved "no Ghostty tab is attached to tmux."
  fi
  if cmp -s "$new_file" "$windows_file"; then
    not_saved "nothing has changed since they were last saved."
  fi
  mv "$new_file" "$windows_file"
  tab_count="$(wc -l < "$windows_file" | tr -d ' ')"
  window_count="$(cut -f 1 "$windows_file" | sort -u | wc -l | tr -d ' ')"
  echo "$(now) Saved $tab_count tab(s) in $window_count Ghostty window(s)"
  exit 0
fi

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

  # Act once per Ghostty launch, and not at all if another run is already
  # bringing the tabs back. The tabs a run opens start shells that run this
  # hook too, before their attach command has run, so without this each one
  # would see detached sessions and open another set of tabs, without end.
  # The same goes for the first tab the LaunchAgent opens at login. Two
  # independent checks: the stamp, and a lock named for this Ghostty process.
  lock_dir="${TMPDIR:-/tmp}/tmux-restore-sessions"
  mkdir -p "$lock_dir" "$state_dir"
  if stamp_is_fresh; then
    exit 1
  fi
  find "$lock_dir" -mindepth 1 -maxdepth 1 -name 'ghostty.*' ! -name "ghostty.$ghostty_pid" -exec rmdir {} + 2>/dev/null || true
  mkdir "$lock_dir/ghostty.$ghostty_pid" 2>/dev/null || exit 1
  touch "$stamp"

  mkdir -p "$(dirname "$log_file")"
  exec >> "$log_file" 2>&1
  echo "$(now) Ghostty started with no tabs attached to tmux"
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

  # From here the tabs are on their way. Say so now, so a Ghostty that starts
  # during the restore leaves them to this run.
  mkdir -p "$state_dir"
  touch "$stamp"

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

# --- Group the sessions into windows -----------------------------------------

# tabs lists what to open: for each tab, a window number, 1 if the tab is
# selected, and the session name. Sessions go where the windows file has them;
# its lines for sessions that aren't being opened are skipped.
newline=$'\n'
session_lines="$newline"
for name in "${sessions[@]}"; do
  session_lines+="$name$newline"
done

tabs=()
placed="$newline"
last_window=0
if [[ -f "$windows_file" ]]; then
  while IFS=$'\t' read -r window selected name; do
    [[ "$window" =~ ^[0-9]+$ && -n "$name" ]] || continue
    [[ "$session_lines" == *"$newline$name$newline"* ]] || continue
    tabs+=("$window" "$selected" "$name")
    placed+="$name$newline"
    if (( window > last_window )); then
      last_window="$window"
    fi
  done < "$windows_file"
fi

# The rest share one more window. With no windows file, that's all of them.
for name in "${sessions[@]}"; do
  if [[ "$placed" != *"$newline$name$newline"* ]]; then
    tabs+=("$((last_window + 1))" 0 "$name")
  fi
done

# The file lists windows front to back, and Ghostty puts each new window in
# front of the last, so open them back to front.
window_numbers="$(for ((i = 0; i < ${#tabs[@]}; i += 3)); do echo "${tabs[i]}"; done | sort -rnu)"
window_count="$(wc -l <<< "$window_numbers" | tr -d ' ')"
ordered=()
for window in $window_numbers; do
  for ((i = 0; i < ${#tabs[@]}; i += 3)); do
    if [[ "${tabs[i]}" == "$window" ]]; then
      ordered+=("${tabs[i]}" "${tabs[i + 1]}" "${tabs[i + 2]}")
    fi
  done
done

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

mkdir -p "$state_dir"
touch "$stamp"

# Each tab starts the usual shell and types the attach command into it, so
# detaching later leaves a normal shell behind.
osascript - "${ordered[@]}" <<'APPLESCRIPT'
on run tabsToOpen
  tell application "Ghostty"
    set win to missing value
    set windowNumber to ""
    set tabCount to 0
    set selections to {}
    repeat with i from 1 to (count of tabsToOpen) by 3
      set cfg to new surface configuration
      set initial input of cfg to "tmux attach-session -t " & quoted form of ("=" & item (i + 2) of tabsToOpen) & linefeed
      if item i of tabsToOpen is not windowNumber then
        set windowNumber to item i of tabsToOpen
        set win to new window with configuration cfg
        set tabCount to 1
      else
        new tab in win with configuration cfg
        set tabCount to tabCount + 1
      end if
      if item (i + 1) of tabsToOpen is "1" then set end of selections to {win, tabCount}
    end repeat
    repeat with chosen in selections
      select tab (tab (item 2 of chosen) of (item 1 of chosen))
    end repeat
    -- The last window opened is the front one; keep it there.
    if win is not missing value then activate window win
    activate
  end tell
end run
APPLESCRIPT

echo "Opened $((${#ordered[@]} / 3)) Ghostty tab(s) in $window_count window(s): ${sessions[*]}"
