# shellcheck shell=bash
# devbox dev-env clojure: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Clojure (official CLI)

Installs clojure@latest with `mise use -g`. Without rlwrap (a pacman package,
lost on a rebuild) `clj` still works, minus the line editing in the REPL: add
rlwrap to the Dockerfile if needed. A removal leaves ~/.m2 and ~/.clojure in
place.
TXT
}

install() { mise use -g clojure@latest; }

uninstall() {
  unuse clojure
  log "~/.m2 and ~/.clojure are left in place."
}
