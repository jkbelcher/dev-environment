# dev-env

Config files and setup scripts for getting a new macOS machine ready for development.

## Contents

| Directory | What it is | Goes to |
| --- | --- | --- |
| `ghostty/` | [Ghostty](https://ghostty.org) terminal config, plus a script that installs Ghostty and the config | `~/.config/ghostty/config` |
| `tmux/` | tmux config, plus scripts that install tmux and the config, and back up `~/.tmux.conf` into this repo | `~/.tmux.conf` |
| `bambu-patches/` | Patch that sets Bambu Studio's default infill pattern to cubic | `~/.config/bambu-patches/` |
| `fusion-to-bambu/` | AppleScript droplet that Fusion's 3D Print command uses to send models to Bambu Studio | `/Applications/Fusion to Bambu.app` |

## Setup

```bash
git clone <this-repo> ~/code/dev-env
cd ~/code/dev-env

# Ghostty (installs the app with Homebrew if it's missing, then copies the
# config; an existing, different config is kept as config.bak.<timestamp>)
./ghostty/install.sh

# tmux (installs tmux with Homebrew if it's missing, then copies the config;
# an existing, different ~/.tmux.conf is kept as .tmux.conf.bak.<timestamp>)
./tmux/install.sh

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
