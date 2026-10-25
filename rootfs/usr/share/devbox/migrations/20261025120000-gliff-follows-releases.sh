#!/usr/bin/env bash
# gliff-server of devbox dev-env desktop, declared before it followed the
# releases of gliff: the first version of the environment pinned the package of
# 0.3.1 with its sha256 in ~/.config/mise/config.toml, so neither `mise
# outdated` nor `devbox update tools` ever saw a new one. The environment now
# declares it at latest (see GLIFF_SPEC in dev-envs/desktop.sh); this brings
# the boxes that installed it earlier onto the same declaration.
#
# Only the declaration that was shipped is replaced: a gliff declared by hand
# is left alone.
set -euo pipefail

CFG="$HOME/.config/mise/config.toml"
OLD_URL="https://pkgs.omarchy.org/edge/x86_64/gliff-0.3.1-1-x86_64.pkg.tar.zst"
OLD_SUM="sha256:73887d4f2e040e7c3a9524ca2aeeac3a5983aa27bbf825ff2027b9ec7bbe3782"

if [ ! -f "$CFG" ] || ! current="$(mise config get -f "$CFG" 'tools.http:gliff' 2>/dev/null)"; then
  echo "  gliff is not declared (devbox dev-env desktop not installed): nothing to do"
  exit 0
fi

if grep -q 'version_list_url' <<<"$current"; then
  echo "  gliff already follows its releases: nothing to do"
  exit 0
fi

if ! grep -qxF "url = \"$OLD_URL\"" <<<"$current" || ! grep -qxF "checksum = \"$OLD_SUM\"" <<<"$current"; then
  echo "  gliff is declared differently from what devbox dev-env desktop shipped: nothing touched"
  exit 0
fi

# shellcheck source=/dev/null
spec="$(. /usr/share/devbox/dev-envs/desktop.sh && echo "$GLIFF_SPEC")"

# mise use keeps the options of an existing entry, the old checksum included:
# the entry goes first, and comes back as it was if the new one cannot install.
backup="$(mktemp)"
trap 'rm -f "$backup"' EXIT
cp "$CFG" "$backup"
mise unuse -g --no-prune http:gliff >/dev/null
if ! mise use -g "$spec"; then
  cp "$backup" "$CFG"
  echo "  the latest gliff could not be installed: the 0.3.1 declaration is back, devbox migrate to try again"
  exit 1
fi
mise prune --yes http:gliff >/dev/null 2>&1 || true
echo "  gliff now follows its releases: $(mise ls --current http:gliff 2>/dev/null | awk '{print $2}')"
echo "  the next ones come with devbox update tools"
