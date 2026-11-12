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
#                                     terminal, output goes to the log. The
#                                     tmux config runs this after every save
#                                     and whenever a tab is attached, focused,
#                                     or resized.
#
# The record is ~/.local/state/tmux-restore-sessions/windows. Tabs come back
# in the same windows, in the same order, with the same tab selected. A
# session whose tab or window was closed keeps the place it had, and sessions
# that never had a tab share one more window. Window position and size aren't
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

# Names the Ghostty process that tabs were last opened in, so the launch hook
# can tell whether its own Ghostty already has them. Written just before the
# tabs are opened.
stamp="$state_dir/stamp"

# Exists while a run is restoring tmux and hasn't opened its tabs yet.
restoring="$state_dir/restoring"

now() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Prints how many seconds ago a file was last written; a large number if it
# doesn't exist.
age_of() {
  local modified
  if modified="$(stat -f %m "$1" 2>/dev/null)"; then
    echo $(( $(date +%s) - modified ))
  else
    echo 999999
  fi
}

# Prints the running Ghostty's pid and start time. The start time is there so
# a later Ghostty that gets the same pid doesn't look like this one.
# (-a: pgrep leaves out its own ancestors otherwise, and Ghostty can be one.)
ghostty_identity() {
  local pid started
  pid="$(pgrep -anx ghostty || true)"
  [[ -n "$pid" ]] || return 1
  started="$(ps -o lstart= -p "$pid" 2>/dev/null || true)"
  [[ -n "$started" ]] || return 1
  # Unquoted, to squeeze the spaces ps pads the date with.
  # shellcheck disable=SC2086
  echo "$pid" $started
}

# --- Save windows ------------------------------------------------------------

# Prints a line for each terminal in Ghostty: window number (1 is the front
# window), tab index, 1 if the tab is selected, window id, and tty, separated
# by tabs. Prints "old VERSION" instead if this Ghostty is too old to report
# ttys.
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
        set windowId to id of win
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
            set out to out & windowNumber & sep & tabIndex & sep & isSelected & sep & windowId & sep & device & linefeed
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

  # tmux runs this with no terminal, after every save and every time a tab is
  # attached, focused, or resized: log only changes and errors there. From a
  # terminal, say what happened.
  quiet=""
  if [[ ! -t 1 ]]; then
    quiet=1
    mkdir -p "$(dirname "$log_file")"
    exec >> "$log_file" 2>&1
  fi
  note() {
    [[ -n "$quiet" ]] || echo "$1"
  }

  # Does one save. Leaves the record alone unless it has something to write.
  new_file=""
  save_windows_once() {
    local delay clients identity terminals old_layout tab_count window_count

    # Tabs that a restore has just opened take a moment to attach. Reading
    # the windows before then would catch only some of them.
    delay=$(( 10 - $(age_of "$stamp") ))
    if (( delay > 0 )); then
      note "Tabs were just opened; giving them $delay second(s) to attach."
      sleep "$delay"
    fi

    # tmux knows the tty each attached client is on.
    clients="$(tmux list-clients -F '#{client_tty} #{session_name}' 2>/dev/null || true)"
    if [[ -z "$clients" ]]; then
      note "Windows not saved: no tmux session is attached."
      return
    fi
    if ! identity="$(ghostty_identity)"; then
      note "Windows not saved: Ghostty isn't running."
      return
    fi

    if ! terminals="$(list_ghostty_terminals 2>&1)"; then
      # Ghostty stops answering while it quits; that isn't worth a log line.
      sleep 2
      if [[ "$(ghostty_identity || true)" == "$identity" ]]; then
        echo "$(now) Couldn't read Ghostty's windows: $terminals"
      else
        note "Windows not saved: Ghostty quit."
      fi
      return
    fi
    if [[ "$terminals" == old\ * ]]; then
      note "Windows not saved: that needs Ghostty 1.4 or later (this is ${terminals#old })."
      return
    fi

    # Match each terminal's tty to the tmux client on it, which gives the
    # window and tab each attached session is in. A session that's still
    # running but has no tab right now (its tab or window was closed, or
    # Ghostty is on its way out) keeps the place the last record gave it:
    # in the same window if that's still open, otherwise in a window of its
    # own with the others that were there. It gets a tab again on the next
    # restore either way.
    #
    # Each line written is: window number (1 is the front window), 1 if the
    # tab is selected, Ghostty's id for the window, and the session name.
    new_file="$(mktemp "$state_dir/windows.XXXXXX")"
    awk -F '\t' '
      kind == "sessions" { alive[$0] = 1; next }
      kind == "clients" {
        space = index($0, " ")
        session_on[substr($0, 1, space - 1)] = substr($0, space + 1)
        next
      }
      kind == "terminals" && NF >= 5 {
        # window number, tab index, selected, window id, tty
        if ($1 + 0 > open_windows) open_windows = $1 + 0
        number_of[$4] = $1
        if ($5 in session_on) {
          print $1 FS $2 FS $3 FS $4 FS session_on[$5]
          has_tab[session_on[$5]] = 1
        }
        next
      }
      kind == "record" && NF >= 4 {
        # window number, selected, window id, session name
        kept++
        was_window[kept] = $1; was_selected[kept] = $2; was_id[kept] = $3; was_name[kept] = $4
        next
      }
      END {
        for (i = 1; i <= kept; i++) {
          name = was_name[i]
          if (!(name in alive) || (name in has_tab)) continue
          if (was_id[i] in number_of) {
            print number_of[was_id[i]] FS (100000 + i) FS 0 FS was_id[i] FS name
          } else {
            print (open_windows + was_window[i]) FS (100000 + i) FS was_selected[i] FS was_id[i] FS name
          }
        }
      }
    ' kind=sessions <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true) \
      kind=clients <(printf '%s\n' "$clients") \
      kind=terminals <(printf '%s\n' "$terminals") \
      kind=record <(cat "$windows_file" 2>/dev/null || true) \
      | sort -s -t "$(printf '\t')" -k 1,1n -k 2,2n \
      | awk -F '\t' -v OFS='\t' '$1 != last { last = $1; window++ } { print window, $3, $4, $5 }' > "$new_file"

    if [[ ! -s "$new_file" ]]; then
      rm -f "$new_file"
      new_file=""
      note "Windows not saved: no Ghostty tab is attached to tmux."
      return
    fi
    if cmp -s "$new_file" "$windows_file"; then
      rm -f "$new_file"
      new_file=""
      note "Windows not saved: nothing has changed since they were last saved."
      return
    fi

    # Which window is in front and which tab is selected change all the time.
    # Without a terminal, log only when a session has changed windows.
    old_layout="$(cut -f 3,4 "$windows_file" 2>/dev/null | sort || true)"
    mv "$new_file" "$windows_file"
    new_file=""
    if [[ -z "$quiet" || "$(cut -f 3,4 "$windows_file" | sort)" != "$old_layout" ]]; then
      tab_count="$(wc -l < "$windows_file" | tr -d ' ')"
      window_count="$(cut -f 1 "$windows_file" | sort -u | wc -l | tr -d ' ')"
      echo "$(now) Saved $tab_count tab(s) in $window_count Ghostty window(s)"
    fi
  }

  # tmux's events come in bursts, so runs can pile up. Each run leaves a
  # request; whichever run holds the lock keeps saving until no request is
  # left, and the others go. A lock a minute or more old was left by a run
  # that was killed.
  pending="$state_dir/pending"
  saving="$state_dir/saving"
  have_lock=""
  finish() {
    [[ -z "$new_file" ]] || rm -f "$new_file"
    [[ -z "$have_lock" ]] || rmdir "$saving" 2>/dev/null || true
  }
  trap finish EXIT

  : > "$pending"
  # (find checks the age and removes the lock in one step. Checking first and
  # removing after would let one run remove a lock another had just taken.)
  find "$saving" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2>/dev/null || true
  passes=0
  while :; do
    if ! mkdir "$saving" 2>/dev/null; then
      note "Another save is already running; it will pick this one up."
      exit 0
    fi
    have_lock=1
    while [[ -e "$pending" ]] && (( passes < 10 )); do
      passes=$((passes + 1))
      # Let a burst finish first, so it takes one save rather than several.
      [[ -z "$quiet" ]] || sleep 0.3
      rm -f "$pending"
      save_windows_once
    done
    rmdir "$saving" 2>/dev/null || true
    have_lock=""
    # A request that arrived just as the lock was let go still needs a run.
    if [[ ! -e "$pending" ]] || (( passes >= 10 )); then
      break
    fi
  done
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
  identity="$(ghostty_identity)" || exit 1
  ghostty_pid="${identity%% *}"
  ghostty_age="$(ps -o etime= -p "$ghostty_pid" | tr -d ' ')"
  [[ "$ghostty_age" =~ ^00:[0-5][0-9]$ ]] || exit 1

  # Act once per Ghostty launch, and not at all while another run is bringing
  # the tabs back. The tabs a run opens start shells that run this hook too,
  # before their attach command has run, so without this each one would see
  # detached sessions and open another set of tabs, without end. The same
  # goes for the first tab the LaunchAgent opens at login.
  #
  # Four checks, any of which is enough:
  #   - another run is restoring tmux and hasn't opened its tabs yet
  #   - tabs were already opened in this Ghostty process
  #   - tabs were opened anywhere in the last five seconds, in case this
  #     Ghostty process couldn't be told apart from the last one
  #   - another shell in this Ghostty process got here first (the lock)
  # None of them stops a Ghostty that was quit and reopened, however quickly.
  lock_dir="${TMPDIR:-/tmp}/tmux-restore-sessions"
  mkdir -p "$lock_dir" "$state_dir"
  if (( $(age_of "$restoring") < 120 )); then
    exit 1
  fi
  if [[ "$(cat "$stamp" 2>/dev/null || true)" == "$identity" ]]; then
    exit 1
  fi
  if (( $(age_of "$stamp") < 5 )); then
    exit 1
  fi
  find "$lock_dir" -mindepth 1 -maxdepth 1 -name 'ghostty.*' ! -name "ghostty.$ghostty_pid" -exec rmdir {} + 2>/dev/null || true
  mkdir "$lock_dir/ghostty.$ghostty_pid" 2>/dev/null || exit 1
  echo "$identity" > "$stamp"

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

  # From here the tabs are on their way. Say so until this run ends, so a
  # Ghostty that starts during the restore leaves them to this run.
  mkdir -p "$state_dir"
  : > "$restoring"
  trap 'rm -f "$restoring"' EXIT

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
  while IFS=$'\t' read -r window selected _ name; do
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

# Say which Ghostty the tabs are going into, for the launch hook in the
# shells they start.
mkdir -p "$state_dir"
ghostty_identity > "$stamp" || : > "$stamp"

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
