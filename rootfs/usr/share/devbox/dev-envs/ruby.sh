# shellcheck shell=bash
# devbox dev-env ruby: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Ruby + Rails

Installs a precompiled ruby@latest with mise (ruby.compile=false: jdx/ruby
publishes x86_64 and arm64 linux builds, no long compile), then the rails gem.
Writes a one line ~/.gemrc (gem: --no-document). A removal deletes that
~/.gemrc only when it was not edited, and leaves the mise settings
ruby.compile and idiomatic_version_file_enable_tools as they are.
TXT
}

install() {
  mise settings add ruby.compile false
  mise settings add idiomatic_version_file_enable_tools ruby
  mise use -g ruby@latest
  echo "gem: --no-document" >"$HOME/.gemrc"
  mise x ruby -- gem install rails --no-document
  log "rails is ready: rails new my-project"
}

uninstall() {
  unuse ruby
  # Only the file install wrote: a ~/.gemrc the user edited is theirs.
  if [ -f "$HOME/.gemrc" ]; then
    if [ "$(cat "$HOME/.gemrc")" = "gem: --no-document" ]; then
      rm -f "$HOME/.gemrc"
      log "~/.gemrc removed (it was the one line written at install)."
    else
      log "~/.gemrc was edited, left in place."
    fi
  fi
  log "the mise settings ruby.compile and idiomatic_version_file_enable_tools are left as they are (harmless without ruby)."
}
