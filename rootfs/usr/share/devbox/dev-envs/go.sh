# shellcheck shell=bash
# devbox dev-env go: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Go, latest stable version

Installs go@latest with `mise use -g`. A removal leaves ~/go (modules,
GOPATH binaries) in place.
TXT
}

install() { mise use -g go@latest; }

uninstall() {
  unuse go
  log "~/go (modules, GOPATH binaries) is left in place."
}
