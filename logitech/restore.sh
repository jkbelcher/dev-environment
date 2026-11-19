#!/usr/bin/env bash
#
# Applies the OpenLogi settings saved by backup.sh (openlogi-settings.toml
# beside this script) to this Mac.
#
# Device settings are saved by model name, so OpenLogi has to have seen the
# device on this Mac first: install OpenLogi, connect the device with OpenLogi
# open, then run this.
#
# It asks before changing anything: once for the general settings, and once
# for each device on this Mac whose model has saved settings. Each time it
# shows the device on this Mac and the saved model, lists the settings that
# would change with the value on this Mac and the saved value, and lists the
# settings that are already the same. Answering yes replaces all of that
# device's settings with the saved ones. Nothing is asked when nothing would
# change.
#
# The previous ~/.config/openlogi/config.toml is kept beside it as
# config.toml.bak.<timestamp>; comments in it aren't carried over. Afterward
# OpenLogi is quit and reopened, which is what makes it load the file. It
# needs Python 3.11 or later and installs it with Homebrew if it's missing.
#
# Usage:
#   ./restore.sh [--file PATH] [--no-relaunch]
#     --file PATH      read PATH instead of openlogi-settings.toml
#     --no-relaunch    don't quit and reopen OpenLogi afterward

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=logitech/find_python.sh
source "$script_dir/find_python.sh"

python_bin="$(find_python)"
exec "$python_bin" -I "$script_dir/openlogi_settings.py" restore "$@"
