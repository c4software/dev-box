# shellcheck shell=bash
# devbox dev-env symfony: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
PHP + symfony-cli

Needs php, checked first. symfony-cli publishes linux amd64 and arm64
binaries, installed through mise's github backend. A removal takes out
symfony-cli only: php stays.
TXT
}

is_installed() { declared "github:symfony-cli/symfony-cli"; }

install() {
  dev_env install php
  mise use -g github:symfony-cli/symfony-cli@latest
  log "symfony is ready: symfony new --webapp my-project"
}

uninstall() {
  unuse github:symfony-cli/symfony-cli
  log "php stays (image package)."
}
