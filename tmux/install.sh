#!/usr/bin/env bash
#
# Installs tmux with Homebrew (unless it's already on PATH), then copies
# tmux.conf.bak next to this script to ~/.tmux.conf.
#
# Also installs TPM and the plugins the config lists (tmux-resurrect and
# tmux-continuum), copies restore-sessions.sh to
# ~/.local/bin/tmux-restore-sessions, sets up a LaunchAgent that runs it at
# login, and adds a hook to ~/.zshrc that runs it when Ghostty starts, so
# sessions come back in their Ghostty windows and tabs after the Mac or
# Ghostty is restarted. (The config has tmux-resurrect run the same script
# after each save, to record which window each tab is in.)
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

# --- Plugins -----------------------------------------------------------------

# The config uses TPM to load tmux-resurrect and tmux-continuum, which save
# sessions so they can be restored after a restart.
tpm_dir="$HOME/.tmux/plugins/tpm"

if [[ -d "$tpm_dir" ]]; then
  echo "TPM is already installed at $tpm_dir"
else
  echo "Installing TPM (the tmux plugin manager)..."
  git clone --quiet --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir"
fi

# TPM's installer asks the tmux server where plugins go, so a server that's
# already running needs the new config first. With no server, tmux reads the
# config when the installer starts one.
tmux_running=""
if "$tmux_bin" list-sessions >/dev/null 2>&1; then
  tmux_running=1
  "$tmux_bin" source-file "$dest_config"
fi

echo "Installing tmux plugins..."
PATH="$(dirname "$tmux_bin"):$PATH" "$tpm_dir/bin/install_plugins"

# Load the plugins that were just installed.
if [[ -n "$tmux_running" ]]; then
  "$tmux_bin" source-file "$dest_config"
fi

# --- Restore at login --------------------------------------------------------

# After a restart, restore-sessions.sh brings the saved sessions back and
# opens a Ghostty tab for each, in the window it was in. A LaunchAgent runs it
# at login. It's copied out of the repo so the agent and the tmux config don't
# depend on where the repo lives.
restore_source="$script_dir/restore-sessions.sh"
restore_dest="$HOME/.local/bin/tmux-restore-sessions"
agent_label="dev-env.tmux-restore-sessions"
agent_plist="$HOME/Library/LaunchAgents/$agent_label.plist"
agent_log="$HOME/Library/Logs/tmux-restore-sessions.log"

mkdir -p "$(dirname "$restore_dest")" "$(dirname "$agent_plist")"
install -m 755 "$restore_source" "$restore_dest"
echo "Installed the restore script to $restore_dest"

cat > "$agent_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$agent_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$restore_dest</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>StandardOutPath</key>
  <string>$agent_log</string>
  <key>StandardErrorPath</key>
  <string>$agent_log</string>
</dict>
</plist>
PLIST

# Loading the agent runs the script once. It does nothing while tmux has
# sessions, or when nothing has been saved yet. If there is a save and tmux
# has no sessions, it restores them and opens their Ghostty tabs.
launchctl bootout "gui/$(id -u)/$agent_label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$agent_plist"
echo "Installed the login agent to $agent_plist"

# --- Restore when Ghostty starts ---------------------------------------------

# Quitting Ghostty can take the tmux server down with it, and the login agent
# doesn't run again until the next login. This hook covers that: the first
# shell of a freshly started Ghostty restores the sessions if tmux has none,
# then closes, leaving the restored tabs. The script decides whether to act;
# see --on-ghostty-launch in restore-sessions.sh.
zshrc="${ZDOTDIR:-$HOME}/.zshrc"
hook_marker="--on-ghostty-launch"

if grep -qF -- "$hook_marker" "$zshrc" 2>/dev/null; then
  echo "The Ghostty launch hook is already in $zshrc"
else
  {
    echo
    echo "# Restore tmux sessions when Ghostty starts without them (added by dev-env/tmux/install.sh)"
    echo "if [[ -o interactive && -n \"\$GHOSTTY_RESOURCES_DIR\" && -z \"\$TMUX\" && -x \"\$HOME/.local/bin/tmux-restore-sessions\" ]]; then"
    echo "  \"\$HOME/.local/bin/tmux-restore-sessions\" --on-ghostty-launch && exit"
    echo "fi"
  } >> "$zshrc"
  echo "Added the Ghostty launch hook to $zshrc"
fi

echo
if [[ -n "$tmux_running" ]]; then
  echo "Done. tmux is running and has the new config."
else
  echo "Done. Start tmux with: tmux"
fi
echo "Sessions are saved every 15 minutes (prefix + S saves now). They come"
echo "back in their Ghostty windows and tabs at login and when Ghostty is"
echo "restarted; the first time, macOS asks for permission to control Ghostty."
