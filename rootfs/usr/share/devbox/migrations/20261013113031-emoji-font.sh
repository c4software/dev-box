#!/usr/bin/env bash
# Boxes that installed a browser or the graphical session before those came
# with an emoji font: noto-fonts has none, so Chromium, headless or on screen,
# and the terminal of the session drew a square for every emoji. The font is a
# package like the others of those environments: it joins the list of
# `devbox pkg`, and the start that runs this migration installs it right
# after, with the rest of that list. devbox dev-env browser and desktop do the
# same on a fresh install.
set -euo pipefail

LIST="$HOME/.config/dev-box/packages"

if [ ! -s "$LIST" ]; then
  echo "  no package kept by devbox pkg: nothing to do"
  exit 0
fi

if ! grep -qxE 'chromium|hyprland' "$LIST"; then
  echo "  neither a browser nor the graphical session here: nothing to do"
  exit 0
fi

if grep -qx 'noto-fonts-emoji' "$LIST"; then
  echo "  noto-fonts-emoji is already in the list of devbox pkg: nothing to do"
  exit 0
fi

echo 'noto-fonts-emoji' >> "$LIST"
echo "  noto-fonts-emoji added to the list of devbox pkg: emojis are drawn once it is installed"
echo "  (at this start, or now with devbox pkg restore)"
