#!/usr/bin/env bash
#
# Saves OpenLogi's settings into this repo, as openlogi-settings.toml beside
# this script. Run it after changing settings in OpenLogi.
#
# OpenLogi files each device's settings under its serial number, which
# mustn't be published, so the backup files them under the model name instead
# ("MX Master 3S") and leaves out everything that names a particular device or
# machine. If two devices of one model have different settings, it asks which
# to save. Settings saved earlier for a model that isn't on this Mac are kept.
#
# It reads ~/.config/openlogi/config.toml (or $XDG_CONFIG_HOME) and doesn't
# change it. It needs Python 3.11 or later and installs it with Homebrew if
# it's missing. Read the diff before committing: device names, and actions
# that open files or type text, are saved as they are.
#
# Usage:
#   ./backup.sh [--file PATH]    PATH replaces openlogi-settings.toml

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=logitech/find_python.sh
source "$script_dir/find_python.sh"

python_bin="$(find_python)"
exec "$python_bin" -I "$script_dir/openlogi_settings.py" backup "$@"
