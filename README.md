# dev-env

Config files and setup scripts for getting a new macOS machine ready for development.

## Contents

| Directory | What it is | Goes to |
| --- | --- | --- |
| `macos/` | Script that applies macOS settings: black desktop, Dock on the right with some Apple apps removed, Finder options and sidebar Favorites, and trackpad settings | macOS settings (`defaults`, Finder sidebar, desktop picture) |
| `ghostty/` | [Ghostty](https://ghostty.org) terminal config, plus a script that installs Ghostty and the config | `~/.config/ghostty/config` |
| `tmux/` | tmux config, plus scripts that install tmux and the config, back up `~/.tmux.conf` into this repo, and bring sessions back in Ghostty tabs after a restart | `~/.tmux.conf`, `~/.tmux/plugins/`, `~/.local/bin/tmux-restore-sessions`, `~/Library/LaunchAgents/dev-env.tmux-restore-sessions.plist` |
| `textmate/` | Script that installs [TextMate](https://macromates.com) and makes it the default editor for text and code files and for `EDITOR` | `/Applications/TextMate.app`, `~/.zshrc` |
| `bambu-default-infill/` | Patch that sets Bambu Studio's default infill pattern to cubic, plus a script that applies it | Bambu Studio's `fdm_process_common.json` (run from the repo; nothing is copied) |
| `fusion-to-bambu/` | AppleScript droplet that Fusion's 3D Print command uses to send models to Bambu Studio | `/Applications/Fusion to Bambu.app` |

## Setup

Install [Homebrew](https://brew.sh) first, then:

```bash
git clone <this-repo> ~/code/dev-env
cd ~/code/dev-env
./install.sh
```

`install.sh` runs the macOS, TextMate, Ghostty, and tmux scripts below, in that order. If one fails, the rest still run and the failures are listed at the end. It's safe to run again. It doesn't install the Bambu items; see [Bambu Studio](#bambu-studio) and [Fusion to Bambu](#fusion-to-bambu).

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
# unless your zsh config already sets an editor)
./textmate/install.sh

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
- **Restoring:** at login, a LaunchAgent runs `tmux/restore-sessions.sh`, which restores the last save and opens one Ghostty window with a tab attached to each session. It needs Ghostty 1.3 or later. The first time, macOS asks for permission to control Ghostty.
- **What doesn't come back:** programs that were running in the panes, apart from the few resurrect restarts by default (such as `vi`, `man`, and `less`). Anything done since the last save is lost too.

The Ghostty config sets `window-save-state = never` so Ghostty doesn't also reopen its old tabs as empty shells.

To open tabs for sessions that are already running (for example, ones you detached from):

```bash
tmux-restore-sessions NAME [NAME...]
```

That needs `~/.local/bin` on your `PATH`; otherwise run `./tmux/restore-sessions.sh` from the repo. Output from the login run goes to `~/Library/Logs/tmux-restore-sessions.log`.

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

After changing `~/.tmux.conf`, copy it back into the repo:

```bash
./tmux/backup_tmux.sh
```
