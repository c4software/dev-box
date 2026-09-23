# shellcheck shell=bash
# devbox dev-env scala: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Java + Scala + scala-cli

Installs java@latest, scala@latest and scala-cli@latest with `mise use -g`. A
removal takes out scala and scala-cli only: java stays.
TXT
}

install() { mise use -g java@latest scala@latest scala-cli@latest; }

uninstall() {
  unuse scala scala-cli
  log "java stays: devbox dev-env --remove java."
}
