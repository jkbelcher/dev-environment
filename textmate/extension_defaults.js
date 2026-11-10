#!/usr/bin/osascript -l JavaScript
//
// Sets the default app for file extensions by saving the entries straight to
// Launch Services' settings, for textmate/install.sh. Launch Services' own
// call for this (the one duti uses) can't do two kinds of extension:
//
//   - Ones no installed app or macOS itself has a file type for (.fish, .go,
//     .rs, ...). macOS makes up a "dyn." type for those, and the call fails
//     with error -50. These get an entry keyed on the extension, as Finder's
//     Open With > Change All saves.
//   - Ones whose file type the app doesn't list as one it opens (TextMate
//     and .css, .yml, .ts). The call reports success but changes nothing.
//     These get the same entry the call saves when it works.
//
// Usage (extensions include the dot):
//
//   osascript -l JavaScript extension_defaults.js set BUNDLE_ID .ext...
//       Makes the app BUNDLE_ID the default for each extension. Launch
//       Services reads these entries only when it starts, so if `check`
//       lists any afterward, restart it: killall -u "$(id -un)" lsd
//
//   osascript -l JavaScript extension_defaults.js check BUNDLE_ID .ext...
//       Prints the extensions whose files don't open in BUNDLE_ID.

ObjC.import('AppKit');

const UTType = $.NSClassFromString('UTType');
const prefsDomain = 'com.apple.LaunchServices/com.apple.launchservices.secure';
const extensionTagClass = 'public.filename-extension';

function print(line) {
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(
    $(line + '\n').dataUsingEncoding($.NSUTF8StringEncoding));
}

function bareExtension(ext) {
  return ext.replace(/^\./, '').toLowerCase();
}

function stringValue(dict, key) {
  const value = dict.objectForKey(key);
  return value.isNil() ? '' : String(ObjC.unwrap(value)).toLowerCase();
}

// What a saved entry for this extension is keyed on: its file type, or the
// extension itself when it has no file type.
function keyForExtension(ext) {
  const type = UTType.typeWithFilenameExtension(bareExtension(ext));
  if (type.isNil() || type.dynamic) {
    return { tag: bareExtension(ext) };
  }
  return { type: type.identifier.js.toLowerCase() };
}

function keyForEntry(entry) {
  const type = stringValue(entry, 'LSHandlerContentType');
  if (type) {
    return 'type:' + type;
  }
  if (stringValue(entry, 'LSHandlerContentTagClass') === extensionTagClass) {
    return 'tag:' + stringValue(entry, 'LSHandlerContentTag');
  }
  return '';
}

function set(bundleId, exts) {
  const app = bundleId.toLowerCase();
  const keys = new Map();  // 'type:...' or 'tag:...' -> the entry's key
  for (const ext of exts) {
    const key = keyForExtension(ext);
    keys.set(key.type ? 'type:' + key.type : 'tag:' + key.tag, { key });
  }

  // Go through the saved entries as Objective-C objects, so the ones for
  // other file types are written back exactly as they were.
  const prefs = $.NSUserDefaults.alloc.initWithSuiteName(prefsDomain);
  const saved = prefs.arrayForKey('LSHandlers');
  const kept = $.NSMutableArray.array;
  const alreadySet = new Set();
  const count = saved.isNil() ? 0 : saved.count;
  for (let i = 0; i < count; i++) {
    const entry = saved.objectAtIndex(i);
    const name = keyForEntry(entry);
    if (keys.has(name)) {
      if (stringValue(entry, 'LSHandlerRoleAll') !== app || alreadySet.has(name)) {
        continue;  // drop entries for another app, and duplicates
      }
      alreadySet.add(name);
    }
    kept.addObject(entry);
  }

  let changed = false;
  for (const [name, { key }] of keys) {
    if (alreadySet.has(name)) {
      continue;
    }
    const entry = key.type
      ? { LSHandlerContentType: key.type }
      : { LSHandlerContentTag: key.tag, LSHandlerContentTagClass: extensionTagClass };
    entry.LSHandlerRoleAll = app;
    entry.LSHandlerPreferredVersions = { LSHandlerRoleAll: '-' };
    kept.addObject($(entry));
    changed = true;
  }
  if (!changed) {
    return;
  }

  prefs.setObjectForKey(kept, 'LSHandlers');
  if (!prefs.synchronize) {
    throw new Error('Couldn\'t save the Launch Services settings');
  }
}

function check(bundleId, exts) {
  const fm = $.NSFileManager.defaultManager;
  const ws = $.NSWorkspace.sharedWorkspace;
  const dir = $.NSTemporaryDirectory().js + 'extension_defaults.' + $.NSUUID.UUID.UUIDString.js;
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError($(dir), true, $(), $());
  try {
    for (const ext of exts) {
      const path = dir + '/file.' + bareExtension(ext);
      fm.createFileAtPathContentsAttributes($(path), $.NSData.data, $());
      const appURL = ws.URLForApplicationToOpenURL($.NSURL.fileURLWithPath($(path)));
      const bundle = appURL.isNil() ? null : $.NSBundle.bundleWithURL(appURL);
      const opensIn = (bundle && !bundle.isNil() && !bundle.bundleIdentifier.isNil())
        ? bundle.bundleIdentifier.js.toLowerCase() : '';
      if (opensIn !== bundleId.toLowerCase()) {
        print(ext);
      }
    }
  } finally {
    fm.removeItemAtPathError($(dir), $());
  }
}

function run(argv) {
  const [command, ...args] = argv;
  if (command === 'set' && args.length > 1) {
    set(args[0], args.slice(1));
  } else if (command === 'check' && args.length > 1) {
    check(args[0], args.slice(1));
  } else {
    throw new Error('Usage: extension_defaults.js set|check BUNDLE_ID .ext...');
  }
}
