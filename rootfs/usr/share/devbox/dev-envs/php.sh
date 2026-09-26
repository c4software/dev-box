# shellcheck shell=bash
# devbox dev-env php: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
PHP + composer + xdebug (image packages, ready to use)

The one exception to "mise only": mise builds PHP from source, which is slow
and needs every header in the image. php, composer, php-sqlite and xdebug are
therefore packages of the image, extensions enabled at build time. Installing
only checks and shows what is there; removing touches nothing. Global composer
packages live in ~/.config/composer and persist.
TXT
}

is_installed() { command -v php >/dev/null 2>&1; }

install() {
  command -v php >/dev/null 2>&1 || {
    err "php is missing from the image: add php composer php-sqlite xdebug to the Dockerfile, then rebuild the container"
    return 1
  }
  log "$(php -v | head -n 1)"
  log "extensions: $(php -m | grep -iE '^(bcmath|intl|pdo_sqlite|pdo_mysql|xdebug|zip|gd)$' | tr '\n' ' ')"
  log "composer $(composer --version 2>/dev/null | awk '{print $3}'), global packages in ~/.config/composer (persistent)"
}

uninstall() {
  log "php, composer and xdebug are packages of the image: nothing to remove from the home."
  log "~/.config/composer (global packages) is left in place."
}
