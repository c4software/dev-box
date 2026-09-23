#!/usr/bin/env bash
# Homes created before the guided tour existed never had the flag the
# entrypoint writes on a brand new home, so the first login never proposed
# it. This lays the flag down once: the next interactive login asks whether
# to take the tour, and removes the flag whatever the answer. dev-box-tour
# --offer is what reads it.
set -euo pipefail

FLAG="$HOME/.config/dev-box/tour-pending"

if [ -f "$FLAG" ]; then
  echo "  the tour is already proposed at the next login: nothing to do"
  exit 0
fi

mkdir -p "$(dirname "$FLAG")"
touch "$FLAG"
echo "  the next login proposes the guided tour of the box (devbox tour any time)"
