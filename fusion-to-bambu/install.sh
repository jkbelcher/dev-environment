#!/usr/bin/env bash
#
# Builds "Fusion to Bambu.app" from the AppleScript source next to this
# script and installs it in /Applications (or the directory passed as $1).
#
# This does the same thing as pasting the script into Script Editor and
# saving it as an Application. The script has an `on open` handler, so
# osacompile builds it as a droplet, which is what lets Fusion hand it
# files. "Stay open after run handler" stays off (that would need -s).
#
# Run it again whenever the .applescript changes.

set -euo pipefail

app_name="Fusion to Bambu"
bundle_id="com.apple.ScriptEditor.id.Fusion-to-Bambu"

script_dir="$(cd "$(dirname "$0")" && pwd)"
source_file="$script_dir/$app_name.applescript"
dest_dir="${1:-/Applications}"
app_path="$dest_dir/$app_name.app"

if [[ ! -d "$dest_dir" ]]; then
  echo "Destination directory does not exist: $dest_dir" >&2
  exit 1
fi

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
built_app="$build_dir/$app_name.app"

osacompile -o "$built_app" "$source_file"

# osacompile leaves out CFBundleIdentifier. Give the app the same ID Script
# Editor would, so macOS privacy settings treat it as the same app, then
# re-sign because the signature covers Info.plist.
plutil -insert CFBundleIdentifier -string "$bundle_id" "$built_app/Contents/Info.plist"
codesign --force --sign - "$built_app" 2>/dev/null

rm -rf "$app_path"
mv "$built_app" "$app_path"

echo "Installed $app_path"
echo
echo "To use it from Fusion: File > 3D Print, set Application to Custom,"
echo "then Browse Application > From my computer > $app_path"
