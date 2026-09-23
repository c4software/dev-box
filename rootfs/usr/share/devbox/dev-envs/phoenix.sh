# shellcheck shell=bash
# devbox dev-env phoenix: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Elixir + hex + rebar + the phx_new generator

Needs elixir, installed first. Adds rebar and the phx_new archive to ~/.mix.
A removal takes out the archive only: elixir, hex and rebar stay.
TXT
}

is_installed() { compgen -G "$HOME/.mix/archives/phx_new*" >/dev/null; }

install() {
  dev_env install elixir
  mise x elixir -- mix local.rebar --force
  mise x elixir -- mix archive.install hex phx_new --force
  log "phoenix is ready: mix phx.new my_app"
}

uninstall() {
  if dev_env is_installed elixir; then
    mise x elixir -- mix archive.uninstall phx_new --force
  else
    # Without elixir, mix cannot run: the archive is a directory under ~/.mix,
    # created by install, so it is removed by hand.
    rm -rf "$HOME/.mix/archives"/phx_new*
    log "phx_new archive removed from ~/.mix/archives."
  fi
  log "elixir, hex and rebar stay: devbox dev-env --remove elixir."
}
