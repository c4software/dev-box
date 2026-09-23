#!/usr/bin/env bash
# The changelog used to be a file of the image, and ~/.config/dev-box/changelog-seen
# held the heading of its newest entry shown. It is now read from the GitHub
# releases, and the file holds the version of the image last shown (v1.7). A
# heading left there is no version: it is removed, so the first login after
# this update shows the latest release notes once, then records the version.
set -euo pipefail

SEEN="$HOME/.config/dev-box/changelog-seen"

if [ ! -f "$SEEN" ]; then
  echo "  no changelog state yet: nothing to do"
  exit 0
fi

seen=""
IFS= read -r seen < "$SEEN" || true
if [[ "$seen" =~ ^v[0-9] ]]; then
  echo "  changelog state already holds a version ($seen): nothing to do"
  exit 0
fi

rm -f "$SEEN"
echo "  old changelog state removed ($seen): the next login shows the latest release notes once"
