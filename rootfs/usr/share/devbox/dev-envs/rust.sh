# shellcheck shell=bash
# devbox dev-env rust: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Rust (toolchain managed by mise, no rustup)

Installs rust@latest with `mise use -g`: mise handles the toolchain itself, a
single source of truth for the versions. A removal leaves ~/.cargo (registry,
cargo install binaries) in place.
TXT
}

install() { mise use -g rust@latest; }

uninstall() {
  unuse rust
  log "~/.cargo (registry, cargo install binaries) is left in place."
}
