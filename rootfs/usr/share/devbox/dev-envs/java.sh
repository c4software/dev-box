# shellcheck shell=bash
# devbox dev-env java: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Java, latest JDK

Installs java@latest with `mise use -g`. A removal leaves ~/.m2 and ~/.gradle
in place.
TXT
}

install() { mise use -g java@latest; }

uninstall() {
  unuse java
  log "~/.m2 and ~/.gradle are left in place."
}
