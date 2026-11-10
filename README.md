# dev-env

Config files and setup scripts for getting a new macOS machine ready for development.

## Contents

| Directory | What it is | Goes to |
| --- | --- | --- |
| `macos/` | Script that applies macOS settings: black desktop, Dock on the right with some Apple apps removed, Finder options and sidebar Favorites, and trackpad settings | macOS settings (`defaults`, Finder sidebar, desktop picture) |
| `ghostty/` | [Ghostty](https://ghostty.org) terminal config, plus a script that installs Ghostty and the config | `~/.config/ghostty/config` |
| `tmux/` | tmux config, plus scripts that install tmux and the config, and back up `~/.tmux.conf` into this repo | `~/.tmux.conf` |
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
# an existing, different ~/.tmux.conf is kept as .tmux.conf.bak.<timestamp>)
./tmux/install.sh
```

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
