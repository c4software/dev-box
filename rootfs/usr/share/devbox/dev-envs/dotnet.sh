# shellcheck shell=bash
# devbox dev-env dotnet: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
.NET SDK

Installs dotnet@latest with `mise use -g`. A removal leaves ~/.nuget in place.
TXT
}

install() { mise use -g dotnet@latest; }

uninstall() {
  unuse dotnet
  log "~/.nuget is left in place."
}
