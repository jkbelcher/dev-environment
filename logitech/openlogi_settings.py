#!/usr/bin/env python3
#
# Backs up and restores OpenLogi's settings. Run it through backup.sh or
# restore.sh, which find a Python new enough to read TOML (3.11 or later).
#
# OpenLogi keeps everything in ~/.config/openlogi/config.toml (or under
# $XDG_CONFIG_HOME), with each device's settings filed under its serial number
# or receiver ID. This repo is public, so the backup files device settings
# under the model name instead ("MX Master 3S") and leaves out everything that
# names a particular device or machine:
#
#   - each device's `identity`, `links`, and `host_switch_targets`
#   - `selected_device` and the whole `[flow]` section
#
# Usage:
#   openlogi_settings.py backup  [--file PATH]
#   openlogi_settings.py restore [--file PATH] [--no-relaunch]
#
# PATH defaults to openlogi-settings.toml beside this script.

import argparse
import copy
import datetime
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import time

try:
    import tomllib
except ImportError:
    sys.exit("This needs Python 3.11 or later. Run backup.sh or restore.sh instead.")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BACKUP = os.path.join(SCRIPT_DIR, "openlogi-settings.toml")

# Top-level config.toml sections that aren't tied to a device or a machine.
GENERAL_SECTIONS = ("app_settings", "keyboard", "apps")
# Parts of a device's entry that describe the hardware and how it's connected.
# OpenLogi writes these itself; restore leaves the local copies alone.
HARDWARE_FIELDS = ("identity", "links", "host_switch_targets")

GUI_BUNDLE_ID = "org.openlogi.openlogi"
GUI_PROCESS = "openlogi-desktop"

BACKUP_HEADER = """\
# OpenLogi settings, saved by logitech/backup.sh. Restore them with
# logitech/restore.sh. Device settings are filed by model name, not by serial
# number. Don't edit this by hand; change the settings in OpenLogi and run
# backup.sh again.

"""


def die(message):
    sys.exit(f"Error: {message}")


def show_path(path):
    """A path for messages, with the home folder written as ~."""
    home = os.path.expanduser("~")
    if path == home or path.startswith(home + os.sep):
        return "~" + path[len(home):]
    return path


# --- TOML ---------------------------------------------------------------------

BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")


def toml_string(text):
    # JSON's escapes are all valid in a TOML basic string. JSON leaves DEL
    # as-is, which TOML doesn't allow.
    return json.dumps(text, ensure_ascii=False).replace("\x7f", "\\u007f")


def toml_key(key):
    return key if BARE_KEY.match(key) else toml_string(key)


def toml_path(path):
    return ".".join(toml_key(part) for part in path)


def toml_value(value):
    """One value on a single line; tables become inline tables."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if value != value:
            return "nan"
        if value in (float("inf"), float("-inf")):
            return "inf" if value > 0 else "-inf"
        return repr(value)
    if isinstance(value, str):
        return toml_string(value)
    if isinstance(value, (datetime.datetime, datetime.date, datetime.time)):
        return value.isoformat()
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = (f"{toml_key(k)} = {toml_value(v)}" for k, v in value.items())
        return "{ " + ", ".join(items) + " }"
    raise TypeError(f"can't write {type(value).__name__} as TOML")


def toml_document(data):
    lines = []

    def emit(table, path):
        values = [(k, v) for k, v in table.items() if not isinstance(v, dict)]
        tables = [(k, v) for k, v in table.items() if isinstance(v, dict)]
        # A table holding only other tables needs no header of its own.
        if path and (values or not tables):
            if lines:
                lines.append("")
            lines.append(f"[{toml_path(path)}]")
        for key, value in values:
            lines.append(f"{toml_key(key)} = {toml_value(value)}")
        for key, value in tables:
            emit(value, path + (key,))

    emit(data, ())
    return "\n".join(lines) + "\n"


def same(a, b):
    """Equal, and of the same types (so 1, 1.0, and true all differ)."""
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, float) and a != a:
        return b != b
    return a == b


def render(data, header=""):
    """`data` as TOML text, checked by reading it back."""
    text = header + toml_document(data)
    if not same(tomllib.loads(text), data):
        die("couldn't write these settings as TOML without changing them. Nothing was saved.")
    return text


def sort_tables(value):
    """A copy with every table's keys in order, so the backup diffs cleanly."""
    if isinstance(value, dict):
        return {key: sort_tables(value[key]) for key in sorted(value)}
    if isinstance(value, list):
        return [sort_tables(item) for item in value]
    return value


def write_atomic(path, text, mode):
    directory = os.path.dirname(path)
    fd, temp = tempfile.mkstemp(dir=directory, prefix=".openlogi-settings.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(temp, mode)
        os.replace(temp, path)
    except BaseException:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


# --- OpenLogi's config --------------------------------------------------------

def config_path():
    # OpenLogi follows the XDG layout on macOS too, and only honors an
    # absolute $XDG_CONFIG_HOME.
    base = os.environ.get("XDG_CONFIG_HOME", "")
    if not os.path.isabs(base):
        base = os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "openlogi", "config.toml")


def read_config():
    path = config_path()
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except FileNotFoundError:
        die(f"OpenLogi hasn't saved any settings yet ({show_path(path)} doesn't exist). "
            "Open OpenLogi once, then run this again.")
    try:
        config = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        die(f"couldn't read {show_path(path)}: {error}")
    if not isinstance(config.get("schema_version"), int):
        die(f"{show_path(path)} has no schema_version, so it can't be matched to a backup.")
    return path, text, config


def general_settings(config):
    return {s: config[s] for s in GENERAL_SECTIONS if config.get(s)}


def device_settings(entry):
    return {k: v for k, v in entry.items() if k not in HARDWARE_FIELDS}


def model_name(entry):
    identity = entry.get("identity") or {}
    for field in ("display_name", "codename"):
        name = identity.get(field)
        if isinstance(name, str) and name.strip():
            return name.strip()
    return None


def device_kind(entry):
    kind = (entry.get("identity") or {}).get("kind")
    return kind if isinstance(kind, str) else None


def alias_references(config):
    """Names of the [apps] aliases that devices' per-app profiles refer to."""
    names = set()
    for entry in config.get("devices", {}).values():
        keys = list(entry.get("per_app_bindings") or {})
        keys += list((entry.get("action_ring") or {}).get("per_app") or {})
        names.update(key[len("app:"):] for key in keys if key.startswith("app:"))
    return names


def flatten(table, prefix=()):
    """{path: value} for every setting in `table`, descending into tables."""
    out = {}
    for key, value in table.items():
        path = prefix + (key,)
        if isinstance(value, dict) and value:
            out.update(flatten(value, path))
        else:
            out[path] = value
    return out


def count(number, noun):
    return f"{number} {noun}" if number == 1 else f"{number} {noun}s"


def ask(question):
    try:
        answer = input(question)
    except EOFError:
        print()
        return ""
    return answer.strip()


def confirm(question):
    return ask(f"{question} [y/N] ").lower() in ("y", "yes")


# --- Backup -------------------------------------------------------------------

def device_tokens(config):
    """Strings that name a particular device or receiver on this Mac."""
    tokens = set()
    keys = []
    for key, entry in config.get("devices", {}).items():
        keys.append(key)
        keys.extend((entry.get("links") or {}).keys())
    selected = config.get("selected_device")
    if isinstance(selected, str):
        keys.append(selected)
    for key in keys:
        tokens.add(key)
        parts = key.split(":")
        # "serial:<s>", "unit:<hex>", "receiver:<uid>:slot:<n>"
        if parts[0] in ("serial", "unit", "receiver") and len(parts) > 1:
            tokens.add(parts[1])
    return {token.lower() for token in tokens if len(token) >= 4}


def strings_in(value, path=()):
    """(path, string) for every key and string value under `value`."""
    if isinstance(value, dict):
        for key, item in value.items():
            yield path + (key,), key
            yield from strings_in(item, path + (key,))
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item, path)
    elif isinstance(value, str):
        yield path, value


def choose_device(name, members):
    """The one device whose settings stand for the model `name`, or None."""
    first = device_settings(members[0][1])
    if all(same(device_settings(entry), first) for _, entry in members[1:]):
        return members[0]
    print(f'{len(members)} devices on this Mac are "{name}", with different settings:')
    for index, (key, entry) in enumerate(members, 1):
        label = f"  {index}. {key}"
        if entry.get("custom_name"):
            label += f', named "{entry["custom_name"]}"'
        label += f" ({count(len(flatten(device_settings(entry))), 'setting')})"
        print(label)
    print("The backup keeps one set of settings per model.")
    answer = ask(f"Save which one? [1-{len(members)}, Enter to skip] ")
    if answer.isdigit() and 1 <= int(answer) <= len(members):
        return members[int(answer) - 1]
    return None


def cmd_backup(args):
    source, _, config = read_config()
    version = config["schema_version"]

    previous = {}
    if os.path.exists(args.file):
        try:
            with open(args.file, "rb") as handle:
                previous = tomllib.load(handle)
        except (OSError, tomllib.TOMLDecodeError) as error:
            print(f"Ignoring the old {show_path(args.file)}, which can't be read: {error}")
    previous_models = previous.get("models") or {}

    groups = {}
    for key, entry in config.get("devices", {}).items():
        name = model_name(entry)
        if name is None:
            print(f"Skipped {key}: OpenLogi hasn't recorded its model name. "
                  "Connect it with OpenLogi open, then run this again.")
            continue
        groups.setdefault(name, []).append((key, entry))

    models = {}
    notes = []
    for name in sorted(groups):
        chosen = choose_device(name, groups[name])
        if chosen is None:
            notes.append(f'Skipped "{name}".')
            continue
        _, entry = chosen
        model = {}
        if device_kind(entry):
            model["kind"] = device_kind(entry)
        model["settings"] = device_settings(entry)
        models[name] = model
    from_this_mac = sorted(models)

    # Models saved from another Mac stay in the backup, as long as they were
    # saved in the config format this Mac uses.
    for name, model in previous_models.items():
        if name in models:
            continue
        if previous.get("schema_version") != version:
            notes.append(f'Dropped the saved settings for "{name}": they were saved in a '
                         "different config format, and weren't replaced from this Mac.")
            continue
        models[name] = model
        if name not in groups:
            notes.append(f'Kept the saved settings for "{name}", which isn\'t on this Mac.')
        else:
            notes.append(f'Kept the settings saved earlier for "{name}".')

    data = {"schema_version": version}
    general = general_settings(config)
    if general:
        data["general"] = general
    data["models"] = models
    data = sort_tables(data)

    tokens = device_tokens(config)
    for path, text in strings_in(data):
        if any(token in text.lower() for token in tokens):
            die(f"the setting {toml_path(path)} names a particular device by its serial "
                "number or receiver ID, which mustn't go in a public repo. Nothing was saved.")

    text = render(data, BACKUP_HEADER)
    try:
        with open(args.file, encoding="utf-8") as handle:
            unchanged = handle.read() == text
    except OSError:
        unchanged = False
    if not unchanged:
        write_atomic(args.file, text, 0o644)

    print(f"Read {show_path(source)}")
    print(f"  General settings: {len(flatten(general))}")
    for name in from_this_mac:
        settings = len(flatten(models[name]["settings"]))
        detail = count(settings, "setting") if settings else "nothing customized yet"
        print(f"  {name}: {detail}")
    for note in notes:
        print(note)
    if unchanged:
        print(f"{show_path(args.file)} is already up to date.")
        return

    print(f"Saved to {show_path(args.file)}")
    home = os.path.expanduser("~")
    with_home = sorted({toml_path(path) for path, value in strings_in(data) if home in value})
    if with_home:
        print()
        print("These settings contain your home folder path, which mustn't be committed:")
        for path in with_home:
            print(f"  {path}")
    print("Read the diff before committing: device names, and actions that open files or")
    print("type text, are saved as they are.")


# --- Restore ------------------------------------------------------------------

MISSING = object()


def compare(local, saved):
    """Split the settings in `local` and `saved` into changed and equal."""
    local_flat, saved_flat = flatten(local), flatten(saved)
    changed, equal = [], []
    for path in sorted(set(local_flat) | set(saved_flat), key=toml_path):
        if path in local_flat and path in saved_flat and same(local_flat[path], saved_flat[path]):
            equal.append((path, local_flat[path]))
        else:
            changed.append((path, local_flat.get(path, MISSING), saved_flat.get(path, MISSING)))
    return changed, equal


def shown(value):
    return "(not set)" if value is MISSING else toml_value(value)


def print_comparison(changed, equal):
    if changed:
        print(f"  Will change ({len(changed)}):")
        for path, local, saved in changed:
            print(f"    {toml_path(path)}")
            print(f"        this Mac: {shown(local)}")
            print(f"        backup:   {shown(saved)}")
    else:
        print("  Nothing to change.")
    if equal:
        print(f"  Already the same, won't change ({len(equal)}):")
        for path, value in equal:
            print(f"    {toml_path(path)} = {shown(value)}")
    print()


def describe(name, kind):
    return f"{name} ({kind})" if kind else name


def write_config(path, original, config):
    """Replace config.toml the way OpenLogi does: locked, checked, atomic."""
    body = render(config)
    target = os.path.realpath(path)
    # OpenLogi holds this lock while it saves, and never deletes the file.
    lock = os.open(target + ".lock", os.O_RDWR | os.O_CREAT, 0o644)
    try:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            die("OpenLogi is saving its settings right now. Nothing was written; run this again.")
        with open(target, encoding="utf-8") as handle:
            current = handle.read()
        if current != original:
            die("config.toml changed while this was running (OpenLogi saved a setting). "
                "Nothing was written; run this again.")
        mode = os.stat(target).st_mode & 0o777
        kept = f"{path}.bak.{time.strftime('%Y%m%d-%H%M%S')}"
        write_atomic(kept, original, mode)
        write_atomic(target, body, mode)
    finally:
        os.close(lock)
    return kept


def gui_running():
    return subprocess.run(["pgrep", "-x", GUI_PROCESS], capture_output=True).returncode == 0


def relaunch():
    """Reopen OpenLogi's window, which is what makes it load config.toml."""
    manual = "Quit and reopen OpenLogi to load the restored settings."
    was_running = gui_running()
    if was_running:
        subprocess.run(["osascript", "-e", f'tell application id "{GUI_BUNDLE_ID}" to quit'],
                       capture_output=True)
        deadline = time.monotonic() + 10
        while gui_running() and time.monotonic() < deadline:
            time.sleep(0.25)
        if gui_running():
            print(manual)
            return
    if subprocess.run(["open", "-b", GUI_BUNDLE_ID], capture_output=True).returncode != 0:
        print(manual)
        return
    verb = "Reopened" if was_running else "Opened"
    print(f"{verb} OpenLogi so it loads the restored settings.")


def cmd_restore(args):
    try:
        with open(args.file, "rb") as handle:
            backup = tomllib.load(handle)
    except FileNotFoundError:
        die(f"there's no backup at {show_path(args.file)}. Run backup.sh first.")
    except tomllib.TOMLDecodeError as error:
        die(f"couldn't read {show_path(args.file)}: {error}")
    saved_version = backup.get("schema_version")
    saved_models = backup.get("models") or {}
    if not isinstance(saved_version, int) or not isinstance(saved_models, dict):
        die(f"{show_path(args.file)} isn't a backup made by backup.sh.")

    path, original, config = read_config()
    version = config["schema_version"]
    print(f"Backup:   {show_path(args.file)}")
    print(f"This Mac: {show_path(path)}")
    print()

    if saved_version != version:
        print(f"The backup was saved in OpenLogi's config format {saved_version}, and this Mac "
              f"uses format {version}.")
        if saved_version > version:
            print("Update OpenLogi on this Mac, then run this again.")
        else:
            print("Run backup.sh on a Mac with an up-to-date OpenLogi to save it in the new format.")
        print("Restoring across formats can leave a config.toml that OpenLogi won't load.")
        if not confirm("Restore anyway?"):
            print("Nothing was changed.")
            return
        print()

    result = copy.deepcopy(config)
    applied = []

    # General settings.
    local_general = general_settings(config)
    saved_general = backup.get("general") or {}
    changed, equal = compare(local_general, saved_general)
    print("General settings (app-wide settings, keyboard remaps, app aliases)")
    print_comparison(changed, equal)
    if changed:
        if confirm("Overwrite the general settings on this Mac with the saved ones?"):
            for section in GENERAL_SECTIONS:
                if saved_general.get(section):
                    result[section] = copy.deepcopy(saved_general[section])
                else:
                    result.pop(section, None)
            applied.append("general settings")
        else:
            print("Left the general settings alone.")
        print()

    # One prompt per device on this Mac whose model has saved settings.
    used = set()
    without_backup = []
    for key, entry in config.get("devices", {}).items():
        name = model_name(entry)
        if name is None:
            continue
        saved = saved_models.get(name)
        if not isinstance(saved, dict):
            without_backup.append(describe(name, device_kind(entry)))
            continue
        used.add(name)
        saved_settings = saved.get("settings") or {}
        changed, equal = compare(device_settings(entry), saved_settings)

        print(name)
        print("  On this Mac:")
        print(f"    Model: {describe(name, device_kind(entry))}")
        if entry.get("custom_name"):
            print(f'    Named: "{entry["custom_name"]}"')
        print(f"    ID:    {key}")
        print("  In the backup:")
        print(f"    Model: {describe(name, saved.get('kind'))}")
        print()
        print_comparison(changed, equal)
        if not changed:
            continue
        if confirm(f"Overwrite this {name}'s settings with the saved ones?"):
            hardware = {k: v for k, v in entry.items() if k in HARDWARE_FIELDS}
            result["devices"][key] = {**hardware, **copy.deepcopy(saved_settings)}
            applied.append(f"{name} ({key})")
        else:
            print(f"Left this {name} alone.")
        print()

    unused = sorted(set(saved_models) - used)
    if unused:
        print("Saved settings that weren't used, because OpenLogi on this Mac hasn't seen")
        print("the device. Connect it with OpenLogi open, then run this again:")
        for name in unused:
            kind = saved_models[name].get("kind") if isinstance(saved_models[name], dict) else None
            print(f"  {describe(name, kind)}")
        print()
    if without_backup:
        print("Devices on this Mac with no saved settings, left alone:")
        for label in without_backup:
            print(f"  {label}")
        print()

    if not applied:
        print("Nothing was changed.")
        return

    # OpenLogi won't load a config where a per-app profile is keyed by an app
    # alias that [apps] doesn't define, which a yes to a device and a no to
    # the general settings (or the other way round) can leave behind.
    for alias in sorted(alias_references(result) - set(result.get("apps") or {})):
        sources = (("the backup", saved_general.get("apps") or {}),
                   ("this Mac", config.get("apps") or {}))
        for origin, aliases in sources:
            if alias in aliases:
                result.setdefault("apps", {})[alias] = copy.deepcopy(aliases[alias])
                print(f'Kept the app alias "{alias}" from {origin}, because a device\'s '
                      "per-app settings use it.")
                break
        else:
            die(f'a device\'s per-app settings use the app alias "{alias}", which neither '
                "the backup nor this Mac defines. Nothing was changed.")

    kept = write_config(path, original, result)
    print(f"Restored: {', '.join(applied)}.")
    print(f"The previous settings are in {show_path(kept)}")
    if args.no_relaunch:
        print("Quit and reopen OpenLogi to load the restored settings.")
    else:
        relaunch()


def main():
    parser = argparse.ArgumentParser(description="Back up and restore OpenLogi settings.")
    commands = parser.add_subparsers(dest="command", required=True)
    backup = commands.add_parser("backup", help="save this Mac's settings into the repo")
    restore = commands.add_parser("restore", help="apply the saved settings to this Mac")
    for command in (backup, restore):
        command.add_argument("--file", default=DEFAULT_BACKUP, metavar="PATH",
                             help="the backup file (default: openlogi-settings.toml here)")
    restore.add_argument("--no-relaunch", action="store_true",
                         help="don't quit and reopen OpenLogi afterward")
    args = parser.parse_args()
    args.file = os.path.abspath(args.file)
    try:
        if args.command == "backup":
            cmd_backup(args)
        else:
            cmd_restore(args)
    except KeyboardInterrupt:
        sys.exit("\nStopped.")


if __name__ == "__main__":
    main()
