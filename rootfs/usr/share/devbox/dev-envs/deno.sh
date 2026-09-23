# shellcheck shell=bash
# devbox dev-env deno: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Deno, JavaScript and TypeScript runtime

Installs deno@latest with `mise use -g`. A removal takes it out of the mise
config and prunes the versions nothing else needs.
TXT
}

install() { mise use -g deno@latest; }

uninstall() { unuse deno; }
