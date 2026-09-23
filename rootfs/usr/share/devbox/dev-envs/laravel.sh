# shellcheck shell=bash
# devbox dev-env laravel: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
PHP + Node + the Laravel installer (composer global)

Needs php and node, installed first. The Laravel installer goes into
composer's global packages, ~/.config/composer/vendor/bin is on the PATH. A
removal takes out the installer only: php and node stay.
TXT
}

is_installed() { composer global show laravel/installer >/dev/null 2>&1; }

install() {
  dev_env install php
  dev_env install node
  composer global require laravel/installer
  log "laravel is ready: laravel new my-project (~/.config/composer/vendor/bin is on the PATH)"
}

uninstall() {
  if composer global show laravel/installer >/dev/null 2>&1; then
    composer global remove laravel/installer
  else
    log "the Laravel installer is not in composer's global packages, nothing to remove."
  fi
  log "php stays (image package); node stays: devbox dev-env --remove node."
}
