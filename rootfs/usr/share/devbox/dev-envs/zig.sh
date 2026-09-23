# shellcheck shell=bash
# devbox dev-env zig: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Zig + zls (language server)

Installs zig@latest and zls@latest with `mise use -g`. A removal takes both
out of the mise config.
TXT
}

install() { mise use -g zig@latest zls@latest; }

uninstall() { unuse zig zls; }
