#!/usr/bin/env bash
#
# Sourced by backup.sh and restore.sh, not run on its own. Defines
# find_python, which prints the path of a Python that can read TOML (3.11 or
# later). If there isn't one, it installs Python with Homebrew first.

find_python() {
  local candidate brew_bin=""

  for candidate in python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    if "$candidate" -I -c 'import tomllib' >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done

  # On a new machine Homebrew may be installed but not on PATH yet.
  for candidate in brew /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -z "$brew_bin" ]] && command -v "$candidate" >/dev/null 2>&1; then
      brew_bin="$(command -v "$candidate")"
    fi
  done

  if [[ -z "$brew_bin" ]]; then
    echo "Python 3.11 or later is needed to read OpenLogi's settings, and" >&2
    echo "Homebrew is needed to install it. Install Homebrew from" >&2
    echo "https://brew.sh, then run this again." >&2
    return 1
  fi

  echo "Installing Python with Homebrew..." >&2
  "$brew_bin" install python >&2

  candidate="$("$brew_bin" --prefix)/bin/python3"
  if "$candidate" -I -c 'import tomllib' >/dev/null 2>&1; then
    echo "$candidate"
    return 0
  fi

  echo "Couldn't find a Python 3.11 or later after installing it." >&2
  return 1
}
