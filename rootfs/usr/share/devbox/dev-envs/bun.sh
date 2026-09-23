# shellcheck shell=bash
# devbox dev-env bun: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Bun, JavaScript runtime and package manager

Installs bun@latest with `mise use -g`. A removal takes it out of the mise
config and prunes the versions nothing else needs.
TXT
}

install() { mise use -g bun@latest; }

uninstall() { unuse bun; }
