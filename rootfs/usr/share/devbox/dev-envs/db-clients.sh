# shellcheck shell=bash
# devbox dev-env db-clients: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Database shells: mongosh, usql, mycli, litecli (mise)

The clients for the servers of `devbox dbs`, which starts the databases
themselves (podman). psql and mariadb (or mysql) are in the image already;
this adds, through mise, updated by `devbox update tools`: mongosh (MongoDB),
usql (one shell for PostgreSQL, MySQL, SQLite, SQL Server and more:
usql mssql://sa:%40dmin123@127.0.0.1/), and mycli (MySQL and MariaDB) and
litecli (SQLite) with completion and highlighting. mycli and litecli are
Python packages: needs python, installed first. pgcli, the same for
PostgreSQL, is in `devbox tui pgcli`. Redis: podman exec -it devbox-redis
redis-cli. A removal takes out these four and leaves python, the histories
and ~/.myclirc in place.
TXT
}

# Functions rather than arrays: a file runs nothing at the top level.
db_clients_tools() { echo mongosh usql pypi:mycli pypi:litecli; }

is_installed() { declared usql && declared pypi:mycli; }

install() {
  local tools
  read -ra tools <<<"$(db_clients_tools)"
  dev_env install python
  mise use -g "${tools[@]/%/@latest}"
  log "mongosh $(mise x mongosh -- mongosh --version), $(mise x usql -- usql --version), $(mise x pypi:mycli -- mycli --version)"
  log "db-clients is ready, the servers come from devbox dbs:"
  log "  mongosh mongodb://admin:admin123@127.0.0.1:27017, mycli -h 127.0.0.1 -u root, usql pg://postgres@127.0.0.1/?sslmode=disable"
}

uninstall() {
  local tools
  read -ra tools <<<"$(db_clients_tools)"
  unuse "${tools[@]}"
  log "python stays: devbox dev-env --remove python. The histories and ~/.myclirc are left in place."
  log "psql and mariadb stay: they come with the image."
}
