# dev-env

Config files and setup scripts for getting a new macOS machine ready for development.

## Contents

| Directory | What it is | Goes to |
| --- | --- | --- |
| `ghostty/` | [Ghostty](https://ghostty.org) terminal config | `~/Library/Application Support/com.mitchellh.ghostty/config` |
| `tmux/` | tmux config, plus a script that backs up `~/.tmux.conf` into this repo | `~/.tmux.conf` |
| `bambu-patches/` | Patch that sets Bambu Studio's default infill pattern to cubic | `~/.config/bambu-patches/` |
| `fusion-to-bambu/` | AppleScript droplet that Fusion's 3D Print command uses to send models to Bambu Studio | `/Applications/Fusion to Bambu.app` |

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
