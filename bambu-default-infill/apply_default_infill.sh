#!/bin/zsh
#
# Sets Bambu Studio's default sparse infill pattern to cubic by applying
# default_infill.patch (next to this script) to Bambu's system process preset.
# Bambu Studio replaces that file when it updates, so run this again after
# each update.

PATCH="${0:A:h}/default_infill.patch"
TARGET="$HOME/Library/Application Support/BambuStudio/system/BBL/process/fdm_process_common.json"

if [[ ! -f "$TARGET" ]]; then
  echo "Target file not found:"
  echo "$TARGET"
  read -k 1 "?Press any key to close..."
  exit 1
fi

if [[ ! -f "$PATCH" ]]; then
  echo "Patch file not found:"
  echo "$PATCH"
  read -k 1 "?Press any key to close..."
  exit 1
fi

echo "Applying BambuStudio patch..."
patch "$TARGET" "$PATCH"

echo
echo "Done."
read -k 1 "?Press any key to close..."
