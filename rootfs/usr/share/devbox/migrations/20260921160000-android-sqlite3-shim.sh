#!/usr/bin/env bash
# Boxes that ran `devbox dev-env android` before the command started dropping
# the sqlite3 binary of the platform-tools zip: its mise shim shadows the
# sqlite3 of the image (/usr/bin/sqlite3, newer) for every shell. Removing the
# binary from the mise install, then regenerating the shims, puts the Arch one
# back first. dev-box-dev-env does the same on a fresh install.
set -euo pipefail

DIR="$HOME/.local/share/mise/installs/http-android-platform-tools/latest-linux/platform-tools"

if [ ! -d "$DIR" ]; then
  echo "  android platform-tools not installed through mise: nothing to do"
  exit 0
fi

if [ ! -e "$DIR/sqlite3" ]; then
  echo "  platform-tools carry no sqlite3 any more: nothing to do"
  exit 0
fi

rm -f "$DIR/sqlite3"
if command -v mise >/dev/null 2>&1; then
  mise reshim
fi
echo "  sqlite3 of the android platform-tools removed: sqlite3 is now /usr/bin/sqlite3"
