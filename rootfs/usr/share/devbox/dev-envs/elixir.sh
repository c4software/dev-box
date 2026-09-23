# shellcheck shell=bash
# devbox dev-env elixir: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Erlang + Elixir + hex

Installs erlang@latest and elixir@latest with `mise use -g`, then hex. A
removal leaves ~/.mix and ~/.hex (hex, rebar, archives) in place, the phoenix
generator included.
TXT
}

install() {
  mise use -g erlang@latest elixir@latest
  mise x elixir -- mix local.hex --force
}

uninstall() {
  unuse erlang elixir
  log "~/.mix and ~/.hex (hex, rebar, archives) are left in place."
  if dev_env is_installed phoenix; then
    log "the phx_new archive in ~/.mix/archives stays: devbox dev-env --remove phoenix takes it out."
  fi
}
