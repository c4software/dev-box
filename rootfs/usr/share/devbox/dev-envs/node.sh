# shellcheck shell=bash
# devbox dev-env node: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Node.js LTS (npm, npx)

Installs node@lts with `mise use -g`. node is also part of the box's base mise
config, so a removal takes it out until `devbox dev-env node` brings it back.
TXT
}

install() { mise use -g node@lts; }

uninstall() {
  unuse node
  log "node is part of the box's base mise config: devbox dev-env node brings it back."
}
