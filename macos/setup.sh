#!/usr/bin/env bash
#
# Applies macOS settings to a new Mac:
#
#   - Desktop: plain black on every display.
#   - Dock: on the right and always shown, with 47-pixel icons, magnification
#     on at its smallest size, and windows minimizing into their app's icon.
#     The Apple apps listed in dock_remove_apps and the Downloads stack are
#     removed; other Dock items are left alone.
#   - Finder: file extensions shown, column view, new windows open to Home,
#     external disks and removable media shown on the desktop, and the
#     sidebar Favorites listed in sidebar_favorites. Recents, AirDrop, and
#     the Tags section are taken out of the sidebar; folders you added
#     yourself are kept, below the ones listed here.
#   - Trackpad: tap to click, natural scrolling off.
#
# Keyboard settings are left at the macOS defaults on purpose.
#
# It only uses tools that come with macOS (defaults, PlistBuddy, osascript),
# so it can run before Homebrew is installed. Safe to run again.

set -euo pipefail

# --- Settings ----------------------------------------------------------------

wallpaper="/System/Library/Desktop Pictures/Solid Colors/Black.png"

# Dock apps to remove, by .app name. A new Mac's Dock has Keynote, Numbers,
# and Pages under their "Creator Studio" names, so both names are listed.
dock_remove_apps=(
  "Maps.app"
  "FaceTime.app"
  "Phone.app"
  "Contacts.app"
  "Reminders.app"
  "Notes.app"
  "TV.app"
  "Music.app"
  "Keynote.app" "Keynote Creator Studio.app"
  "Numbers.app" "Numbers Creator Studio.app"
  "Pages.app" "Pages Creator Studio.app"
  "Games.app"
  "iPhone Mirroring.app"
)

# Finder sidebar Favorites, top to bottom.
sidebar_favorites=(
  "$HOME"
  "/Applications"
  "$HOME/Desktop"
  "$HOME/Documents"
  "$HOME/Downloads"
)

# --- Helpers -----------------------------------------------------------------

pb() { /usr/libexec/PlistBuddy "$@"; }

contains() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Prints the path a Dock tile points to. Tiles store either a file:// URL with
# %-escapes or a plain path, depending on who wrote them.
dock_tile_path() {
  local plist="$1" entry="$2" url
  url="$(pb -c "Print :$entry:tile-data:file-data:_CFURLString" "$plist" 2>/dev/null)" || return 0
  url="${url#file://}"
  url="${url%/}"
  printf '%b' "${url//%/\\x}"
}

# --- Desktop -----------------------------------------------------------------

if [[ ! -f "$wallpaper" ]]; then
  echo "Skipped the desktop: $wallpaper isn't on this Mac" >&2
elif osascript -l JavaScript - "$wallpaper" <<'JS'
ObjC.import('AppKit');
function run(argv) {
  const url = $.NSURL.fileURLWithPath(argv[0]);
  const workspace = $.NSWorkspace.sharedWorkspace;
  const screens = $.NSScreen.screens;
  for (let i = 0; i < screens.count; i++) {
    const error = Ref();
    if (!workspace.setDesktopImageURLForScreenOptionsError(url, screens.objectAtIndex(i), $({}), error)) {
      throw new Error('Could not set the desktop picture: ' + ObjC.unwrap(error[0].localizedDescription));
    }
  }
}
JS
then
  echo "Set the desktop to black"
else
  echo "Couldn't set the desktop picture (see the error above). Continuing." >&2
fi

# --- Dock --------------------------------------------------------------------

defaults write com.apple.dock orientation -string "right"   # left | bottom | right
defaults write com.apple.dock tilesize -int 47              # icon size in pixels
defaults write com.apple.dock magnification -bool true      # magnification on,
defaults write com.apple.dock largesize -int 16             # at its smallest size
defaults write com.apple.dock autohide -bool false
defaults write com.apple.dock minimize-to-application -bool true

# Edit a copy of the Dock's settings, then load it back if anything changed.
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
dock_plist="$work_dir/dock.plist"
defaults export com.apple.dock "$dock_plist"

removed=""
i=0
while pb -c "Print :persistent-apps:$i" "$dock_plist" >/dev/null 2>&1; do
  app="$(dock_tile_path "$dock_plist" "persistent-apps:$i")"
  app="${app##*/}"
  if [[ -n "$app" ]] && contains "$app" "${dock_remove_apps[@]}"; then
    pb -c "Delete :persistent-apps:$i" "$dock_plist"
    removed="$removed, ${app%.app}"
  else
    i=$((i + 1))
  fi
done

i=0
while pb -c "Print :persistent-others:$i" "$dock_plist" >/dev/null 2>&1; do
  folder="$(dock_tile_path "$dock_plist" "persistent-others:$i")"
  relative="$(pb -c "Print :persistent-others:$i:tile-data:home\ directory\ relative" "$dock_plist" 2>/dev/null || true)"
  if [[ "$folder" == "$HOME/Downloads" || "$relative" == "~/Downloads" ]]; then
    pb -c "Delete :persistent-others:$i" "$dock_plist"
    removed="$removed, Downloads stack"
  else
    i=$((i + 1))
  fi
done

if [[ -n "$removed" ]]; then
  defaults import com.apple.dock "$dock_plist"
  echo "Removed from the Dock: ${removed#, }"
else
  echo "Nothing to remove from the Dock"
fi

# --- Finder ------------------------------------------------------------------

defaults write NSGlobalDomain AppleShowAllExtensions -bool true      # show file extensions
defaults write com.apple.finder FXPreferredViewStyle -string "clmv"  # Nlsv=list, icnv=icon, clmv=column, glyv=gallery
defaults write com.apple.finder NewWindowTarget -string "PfHm"       # new windows open to Home
defaults write com.apple.finder NewWindowTargetPath -string "file://$HOME/"
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
defaults write com.apple.finder ShowRecentTags -bool false           # no Tags section in the sidebar

# Sidebar Favorites. Each listed folder is removed and added back so they end
# up at the top in order; other folders stay below them. Items that aren't
# folders (Recents is a saved search in /System, AirDrop isn't a file) are
# removed.
osascript -l JavaScript - "${sidebar_favorites[@]}" <<'JS'
ObjC.import('CoreServices');

const resolveFlags = 3; // kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes

function entries(list) {
  const items = ObjC.castRefToObject($.LSSharedFileListCopySnapshot(list, Ref()));
  const result = [];
  for (let i = 0; i < items.count; i++) {
    const item = items.objectAtIndex(i);
    const url = $.LSSharedFileListItemCopyResolvedURL(item, resolveFlags, $());
    result.push({ item: item, url: url ? ObjC.castRefToObject(url) : null });
  }
  return result;
}

function displayName(item) {
  return ObjC.castRefToObject($.LSSharedFileListItemCopyDisplayName(item)).js;
}

function run(paths) {
  const list = $.LSSharedFileListCreate($(), $.kLSSharedFileListFavoriteItems, $());
  const removed = [];

  // Items that can't be resolved right now (say, a folder on a drive that
  // isn't plugged in) have no URL and are left alone.
  for (const entry of entries(list)) {
    if (!entry.url) continue;
    const isFolder = entry.url.isFileURL && !entry.url.path.js.startsWith('/System/');
    if (!isFolder) {
      removed.push(displayName(entry.item));
      $.LSSharedFileListItemRemove(list, entry.item);
    }
  }

  let after = $.kLSSharedFileListItemBeforeFirst;
  for (const path of paths) {
    for (const entry of entries(list)) {
      if (entry.url && entry.url.path.js === path) {
        $.LSSharedFileListItemRemove(list, entry.item);
      }
    }
    const url = $.NSURL.fileURLWithPathIsDirectory(path, true);
    after = $.LSSharedFileListInsertItemURL(list, after, $(), $(), url, $(), $());
    if (!after) throw new Error('Could not add ' + path + ' to the Finder sidebar');
  }

  const lines = ['Set the Finder sidebar Favorites'];
  if (removed.length) lines.push('Removed from the Finder sidebar: ' + removed.join(', '));
  return lines.join('\n');
}
JS

# --- Trackpad ----------------------------------------------------------------

defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true                 # tap to click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false            # natural scrolling off

# --- Restart affected apps ---------------------------------------------------

for app in Dock Finder; do
  killall "$app" >/dev/null 2>&1 || true
done

echo
echo "Done. Log out and back in for the trackpad settings to take effect."
