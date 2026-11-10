# dev-env

Config files and setup scripts for getting a new macOS machine ready for development.

## Contents

| Directory | What it is | Goes to |
| --- | --- | --- |
| `ghostty/` | [Ghostty](https://ghostty.org) terminal config | `~/Library/Application Support/com.mitchellh.ghostty/config` |
| `tmux/` | tmux config, plus a script that backs up `~/.tmux.conf` into this repo | `~/.tmux.conf` |
| `bambu-patches/` | Patch that sets Bambu Studio's default infill pattern to cubic | `~/.config/bambu-patches/` |

## Setup

```bash
git clone <this-repo> ~/code/dev-env
cd ~/code/dev-env

# Ghostty
mkdir -p ~/Library/Application\ Support/com.mitchellh.ghostty
cp ghostty/config ~/Library/Application\ Support/com.mitchellh.ghostty/config

# tmux
cp tmux/tmux.conf.bak ~/.tmux.conf

# Bambu Studio (run again after Bambu Studio updates)
mkdir -p ~/.config/bambu-patches
cp bambu-patches/* ~/.config/bambu-patches/
~/.config/bambu-patches/apply_default_infill.sh
```

## Updating

After changing `~/.tmux.conf`, copy it back into the repo:

```bash
./tmux/backup_tmux.sh
```
