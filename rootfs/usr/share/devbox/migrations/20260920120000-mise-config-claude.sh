#!/usr/bin/env bash
# mise config of the boxes created before claude and codex arrived.
#
# The very first shipped version declared node, pi (through
# npm:@earendil-works/pi-coding-agent) and omp, but neither claude nor codex.
# The seed cannot replace it: it is "identical to the reference" only for the
# boxes that already had the reference, and the older ones have none, so
# dev-box-seed adopts it as-is and never touches it again.
#
# This migration only replaces the file when it is word for word one of the
# versions shipped back then: a config changed by hand is never overwritten.
set -euo pipefail

CFG="$HOME/.config/mise/config.toml"

# sha256 of the versions shipped back then that declare neither claude nor codex.
OLD_SUMS=(
  5f70393fcc9f39339bef540b9bbfae21e265837b0c484cb3313e70d5e7d8c3fe
)

if [ ! -f "$CFG" ]; then
  echo "  ~/.config/mise/config.toml is missing: nothing to do (dev-box-seed will lay it down)"
  exit 0
fi

if grep -Eq '^[[:space:]]*"?(claude|codex)"?[[:space:]]*=' "$CFG"; then
  echo "  mise config already up to date (claude or codex declared): nothing to do"
  exit 0
fi

sum="$(sha256sum "$CFG" | awk '{print $1}')"
if ! printf '%s\n' "${OLD_SUMS[@]}" | grep -qxF "$sum"; then
  echo "  mise config changed locally: nothing overwritten"
  echo "  to take the shipped version: devbox seed --force ~/.config/mise/config.toml"
  exit 0
fi

dev-box-seed --force "$CFG"
echo "  mise config replaced by the shipped version (claude and codex declared)"
echo "  to install them: devbox update tools"
