# shellcheck shell=bash
# devbox dev-env python: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Python + uv (packages and virtual environments)

Installs python@latest and uv@latest with `mise use -g`. uv comes from the mise
registry rather than the astral.sh installer: no `curl | sh` in the box. A
removal leaves ~/.cache/uv and the virtual environments in place.
TXT
}

install() { mise use -g python@latest uv@latest; }

uninstall() {
  unuse python uv
  log "~/.cache/uv and the virtual environments are left in place."
}
