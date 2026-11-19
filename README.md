# Dev Environment

Scripts for applying a preferred environment to a macOS machine.

## Contents

| Directory | What it is | Goes to |
| --- | --- | --- |
| `macos/` | Script that applies macOS settings: black desktop, Dock on the right with some Apple apps and the Downloads stack removed, Finder options and sidebar Favorites, and trackpad settings | macOS settings (`defaults`, Finder sidebar, desktop picture) |
| `ghostty/` | [Ghostty](https://ghostty.org) terminal config, plus a script that installs Ghostty and the config | `~/.config/ghostty/config` |
| `tmux/` | tmux config, plus scripts that install tmux and the config, back up `~/.tmux.conf` into this repo, and bring sessions back in their Ghostty windows and tabs after the Mac or Ghostty restarts | `~/.tmux.conf`, `~/.tmux/plugins/`, `~/.local/bin/tmux-restore-sessions`, `~/Library/LaunchAgents/dev-environment.tmux-restore-sessions.plist`, a hook in `~/.zshrc`, `~/.local/state/tmux-restore-sessions/` and `~/Library/Logs/tmux-restore-sessions.log` (written as you work) |
| `textmate/` | Script that installs [TextMate](https://macromates.com) and makes it the default editor for text and code files and for `EDITOR` and `VISUAL` | `/Applications/TextMate.app`, the `mate` command in Homebrew's `bin`, `~/.zshrc`, Launch Services default apps |
| `git/` | Git shortcuts for zsh (`gs` for `git status`, `gcb` for `git checkout -b`, and the rest in `git/aliases.zsh`), plus a script that installs them | `~/.config/zsh/git-aliases.zsh`, `~/.zshrc` |
| `bambu/default-infill/` | Patch that sets Bambu Studio's default infill pattern to cubic, plus a script that applies it | Bambu Studio's `fdm_process_common.json` (run from the repo; nothing is copied) |
| `bambu/fusion-to-bambu/` | AppleScript droplet that Fusion's 3D Print command uses to send models to Bambu Studio | `/Applications/Fusion to Bambu.app` |
| `logitech/` | Script that installs [OpenLogi](https://openlogi.org), a local-first alternative to Logitech Options+, plus its saved settings and scripts that back them up and restore them | `/Applications/OpenLogi.app`, `~/.config/openlogi/config.toml` |

## Setup

Install [Homebrew](https://brew.sh) first, then:

```bash
git clone <this-repo> ~/code/dev-environment
cd ~/code/dev-environment
./install.sh
```

`install.sh` runs the macOS, TextMate, git, Ghostty, and tmux scripts below, in that order. If one fails, the rest still run and the failures are listed at the end. It's safe to run again. It doesn't install the Bambu items or OpenLogi; see [Bambu Studio](#bambu-studio), [Fusion to Bambu](#fusion-to-bambu), and [OpenLogi](#openlogi).

### Running the scripts one at a time

```bash
# macOS settings (black desktop, Dock on the right without the Downloads stack
# or the Apple apps listed at the top of the script, Finder options and
# sidebar Favorites, trackpad). Leaves keyboard settings alone. Needs nothing
# installed first. Log out and back in afterward for the trackpad settings.
./macos/setup.sh

# TextMate (installs the app with Homebrew if it's missing, makes it the
# default app for the text and code file types listed at the top of the
# script, links the mate command, and sets EDITOR and VISUAL to `mate -w` in
# ~/.zshrc unless your zsh config already sets an editor). It restarts Launch
# Services to load the new default apps. If you later install an app that adds
# its own file type for one of the extensions (Xcode does for .toml and .tsx),
# run it again.
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
- **Saving windows:** `tmux/restore-sessions.sh --save-windows` records which Ghostty window and tab each session is in, in `~/.local/state/tmux-restore-sessions/windows`. The tmux config runs it after each of those saves and whenever a tab is attached, changes session, gains or loses focus, or is resized, so the record keeps up as you move tabs between windows. For that the config turns on tmux's `focus-events`. This part needs Ghostty 1.4 or later. The first time, macOS may ask for permission for tmux to control Ghostty.
- **Restoring:** `tmux/restore-sessions.sh` restores the last save and opens a Ghostty tab attached to each session. Tabs come back in the windows they were in, in the same order, with the same tab selected. A session whose tab or window you closed keeps the place it had, and sessions that never had a tab share one more window. Without a record of the windows (or on Ghostty 1.3), every session goes in one window. It runs at login (a LaunchAgent) and when Ghostty starts with no tabs attached to tmux (a hook in `~/.zshrc`, which acts once per Ghostty launch, in the first minute after Ghostty starts). It needs Ghostty 1.3 or later. The first time, macOS asks for permission to control Ghostty.
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
./bambu/default-infill/apply_default_infill.sh
```

### Fusion to Bambu

```bash
./bambu/fusion-to-bambu/install.sh
```

This builds `Fusion to Bambu.app` from `bambu/fusion-to-bambu/Fusion to Bambu.applescript` and puts it in `/Applications`. It does what saving the script as an Application in Script Editor would do. Run it again after you edit the script.

Then, in Fusion: **File > 3D Print**, set **Application** to **Custom**, and choose **Browse Application > From my computer > Applications/Fusion to Bambu**.

### OpenLogi

```bash
./logitech/install.sh
```

This installs [OpenLogi](https://openlogi.org) with Homebrew, unless it's already in `/Applications` or `~/Applications`.

To bring over the settings saved in `logitech/openlogi-settings.toml`, open OpenLogi, connect each mouse and keyboard so OpenLogi sees it, then:

```bash
./logitech/restore.sh
```

OpenLogi files each device's settings (button actions, per-app overrides, DPI, and so on) under its serial number. This repo is public, so the backup files them under the model name instead, such as "MX Master 3S", and the restore applies them to every device of that model that OpenLogi has seen on this Mac.

- **It asks first.** There's one question for the general settings and one for each device. Each shows the device on this Mac and the saved model, the settings that would change with both values, and the settings that are already the same. Yes replaces all of that device's settings with the saved ones. Nothing is asked where nothing would change.
- **The old file is kept** beside the new one as `config.toml.bak.<timestamp>`. Comments in it aren't carried over.
- **OpenLogi is quit and reopened** afterward, which is what makes it load the file. Pass `--no-relaunch` to do that yourself.
- **What isn't saved:** which receiver or cable a device connects through and any setting made for one connection only, a keyboard's list of mice that follow its host switch, and Flow pairings. Set those up again on the new Mac.
- **OpenLogi versions:** the backup records the config format it was saved in. If this Mac's OpenLogi uses a different one, the restore says so and asks before going on.

Both scripts need Python 3.11 or later and install it with Homebrew if it's missing.

## Updating

To change the git shortcuts, edit `git/aliases.zsh`, then install the new copy:

```bash
./git/install.sh
```

To change the Ghostty config, edit `ghostty/config`, then install the new copy:

```bash
./ghostty/install.sh
```

After changing `~/.tmux.conf`, copy it back into the repo:

```bash
./tmux/backup_tmux.sh
```

After changing settings in OpenLogi, save them into the repo. If two devices of one model have different settings, it asks which to save. Read the diff before committing, since device names and actions that open files or type text are saved as they are:

```bash
./logitech/backup.sh
```

After changing `tmux/restore-sessions.sh`, install the new copy. tmux, the login agent, and the Ghostty hook all run the one in `~/.local/bin`, not the one in the repo:

```bash
./tmux/install.sh
```

## Working on this repo

This repo is public, so a commit hook checks each commit before it's made. Set it up once per clone:

```bash
brew install gitleaks shellcheck
```

```bash
git config core.hooksPath hooks
```

`hooks/pre-commit` then blocks a commit when:

- [gitleaks](https://github.com/gitleaks/gitleaks) finds a secret (API key, token, private key, and so on), a home directory path written out in full, or an email address in the staged changes. The rules are in `.gitleaks.toml`.
- [shellcheck](https://www.shellcheck.net) finds a problem in a staged sh or bash script. zsh scripts are skipped, since shellcheck can't read them.

If gitleaks flags something that's fine to publish, end that line with a `gitleaks:allow` comment. For a shellcheck finding that's intended, add a `# shellcheck disable=SCxxxx` comment that says why. Don't skip the hook with `--no-verify`.

`.github/workflows/checks.yml` runs the same checks on GitHub for every push and pull request, with gitleaks scanning the full history. `.github/dependabot.yml` proposes updates to the GitHub Actions the workflow uses.
