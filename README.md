# Dev Environment

Scripts for applying a preferred environment to a macOS machine.

## Contents

| Directory | What it is | Goes to |
| --- | --- | --- |
| `macos/` | Script that applies macOS settings: black desktop, Dock on the right with some Apple apps removed, Finder options and sidebar Favorites, and trackpad settings | macOS settings (`defaults`, Finder sidebar, desktop picture) |
| `ghostty/` | [Ghostty](https://ghostty.org) terminal config, plus a script that installs Ghostty and the config | `~/.config/ghostty/config` |
| `tmux/` | tmux config, plus scripts that install tmux and the config, back up `~/.tmux.conf` into this repo, and bring sessions back in their Ghostty windows and tabs after the Mac or Ghostty restarts | `~/.tmux.conf`, `~/.tmux/plugins/`, `~/.local/bin/tmux-restore-sessions`, `~/Library/LaunchAgents/dev-env.tmux-restore-sessions.plist`, a hook in `~/.zshrc`, `~/.local/state/tmux-restore-sessions/` (written as you work) |
| `textmate/` | Script that installs [TextMate](https://macromates.com) and makes it the default editor for text and code files and for `EDITOR` | `/Applications/TextMate.app`, `~/.zshrc`, Launch Services default apps |
| `git/` | Git shortcuts for zsh (`gs` for `git status`, `gcb` for `git checkout -b`, and the rest in `git/aliases.zsh`), plus a script that installs them | `~/.config/zsh/git-aliases.zsh`, `~/.zshrc` |
| `bambu-default-infill/` | Patch that sets Bambu Studio's default infill pattern to cubic, plus a script that applies it | Bambu Studio's `fdm_process_common.json` (run from the repo; nothing is copied) |
| `fusion-to-bambu/` | AppleScript droplet that Fusion's 3D Print command uses to send models to Bambu Studio | `/Applications/Fusion to Bambu.app` |

## Setup

Install [Homebrew](https://brew.sh) first, then:

```bash
git clone <this-repo> ~/code/dev-env
cd ~/code/dev-env
./install.sh
```

`install.sh` runs the macOS, TextMate, git, Ghostty, and tmux scripts below, in that order. If one fails, the rest still run and the failures are listed at the end. It's safe to run again. It doesn't install the Bambu items; see [Bambu Studio](#bambu-studio) and [Fusion to Bambu](#fusion-to-bambu).

### Running the scripts one at a time

```bash
# macOS settings (black desktop, Dock on the right with the Apple apps listed
# at the top of the script removed, Finder options and sidebar Favorites,
# trackpad). Leaves keyboard settings alone. Needs nothing installed first.
# Log out and back in afterward for the trackpad settings.
./macos/setup.sh

# TextMate (installs the app with Homebrew if it's missing, makes it the
# default app for the text and code file types listed at the top of the
# script, links the mate command, and sets EDITOR to `mate -w` in ~/.zshrc
# unless your zsh config already sets an editor). It restarts Launch Services
# to load the new default apps. If you later install an app that adds its own
# file type for one of the extensions (Xcode does for .toml and .tsx), run it
# again.
./textmate/install.sh

# Git shortcuts (copies git/aliases.zsh to ~/.config/zsh/git-aliases.zsh and
# loads it from ~/.zshrc; an existing, different copy is kept as
# git-aliases.zsh.bak.<timestamp>). Needs nothing installed first. Also lists
# any of the same aliases set elsewhere in your zsh config, to delete by hand.
./git/install.sh

# Ghostty (installs the app with Homebrew if it's missing, then copies the
# config; an existing, different config is kept as config.bak.<timestamp>)
./ghostty/install.sh

# tmux (installs tmux with Homebrew if it's missing, then copies the config;
# an existing, different ~/.tmux.conf is kept as .tmux.conf.bak.<timestamp>.
# Also installs the tmux plugins and the login agent described under
# "Restoring tmux sessions after a restart")
./tmux/install.sh
```

### Restoring tmux sessions after a restart

`tmux/install.sh` sets this up; there's nothing to do by hand.

- **Saving:** the [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) plugins save every session's windows, panes, working directories, and on-screen text every 15 minutes. Press prefix + `S` to save right away, such as before a restart.
- **Saving windows:** after each of those saves, `tmux/restore-sessions.sh --save-windows` records which Ghostty window and tab each session is in, in `~/.local/state/tmux-restore-sessions/windows`. This part needs Ghostty 1.4 or later. The first time, macOS may ask for permission for tmux to control Ghostty.
- **Restoring:** `tmux/restore-sessions.sh` restores the last save and opens a Ghostty tab attached to each session. Tabs come back in the windows they were in, in the same order, with the same tab selected. Sessions that had no tab share one more window. Without a record of the windows (or on Ghostty 1.3), every session goes in one window. It runs at login (a LaunchAgent) and when Ghostty starts with no tabs attached to tmux (a hook in `~/.zshrc`, which only acts in the first minute after Ghostty starts). It needs Ghostty 1.3 or later. The first time, macOS asks for permission to control Ghostty.
- **What doesn't come back:** programs that were running in the panes, apart from the few resurrect restarts by default (such as `vi`, `man`, and `less`). Anything done since the last save is lost too. Windows come back wherever macOS puts them, not at their old position and size. A Ghostty tab split into several terminals comes back as a tab for each, and tabs that weren't in tmux don't come back.

The Ghostty config sets `window-save-state = never` so Ghostty doesn't also reopen its old tabs as empty shells.

To open tabs for sessions that are already running (for example, ones you detached from):

```bash
tmux-restore-sessions NAME [NAME...]
```

That needs `~/.local/bin` on your `PATH`; otherwise run `./tmux/restore-sessions.sh` from the repo. Output from the login run, the Ghostty hook, and the window saves goes to `~/Library/Logs/tmux-restore-sessions.log`.

### Bambu Studio

```bash
# Run again after Bambu Studio updates
./bambu-default-infill/apply_default_infill.sh
```

### Fusion to Bambu

```bash
./fusion-to-bambu/install.sh
```

This builds `Fusion to Bambu.app` from `fusion-to-bambu/Fusion to Bambu.applescript` and puts it in `/Applications`. It does what saving the script as an Application in Script Editor would do. Run it again after you edit the script.

Then, in Fusion: **File > 3D Print**, set **Application** to **Custom**, and choose **Browse Application > From my computer > Applications/Fusion to Bambu**.

## Updating

To change the git shortcuts, edit `git/aliases.zsh`, then install the new copy:

```bash
./git/install.sh
```

After changing `~/.tmux.conf`, copy it back into the repo:

```bash
./tmux/backup_tmux.sh
```
