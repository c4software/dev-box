# shellcheck shell=bash
# devbox dev-env swift: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Swift toolchain (swift, swift build, sourcekit-lsp), no lldb

swift.org publishes no build for Arch: mise takes the Red Hat UBI 9 one, which
asks for two things Arch no longer has. libxml2.so.2 comes from the
libxml2-legacy package, through `devbox pkg`, which puts it back after a
rebuild. The ncurses libraries without wide characters (libncurses.so.6,
libform.so.6, libpanel.so.6) are links to the wide ones of the image, laid
inside the toolchain itself, where its binaries look first: nothing in /usr,
no LD_LIBRARY_PATH. The version is pinned to the one of the day, since a
version `devbox update tools` installed would come without those links: remove
then install again to move to a newer Swift. lldb does not start, it wants
the Python 3.9 of UBI 9: the ios environment brings it. linux x86_64 only. A
removal leaves ~/.swiftpm and ~/.cache/org.swift.swiftpm in place.
TXT
}

is_supported() {
  [ "$(uname -m)" = "x86_64" ] && return 0
  echo "the Swift toolchain has only been made to run on Arch for x86_64"
  return 1
}

# The directory every binary of the toolchain searches before the system's
# (their RUNPATH is $ORIGIN/../lib/swift/linux).
swift_lib_dir() { echo "$(mise where swift)/usr/lib/swift/linux"; }

# libncurses.so.6 and its two companions, as links to the wide builds: the
# same code, which Arch only ships under the w names.
alias_ncurses() {
  local dir="$1" lib
  for lib in ncurses form panel; do
    ln -sf "/usr/lib/lib${lib}w.so.6" "$dir/lib$lib.so.6"
  done
}

install() {
  dev-box-pkg add libxml2-legacy
  local version aliases
  if declared swift; then
    version="$(mise current swift)"
    log "swift already declared: $version"
  else
    version="$(mise latest swift)"
  fi
  # mise runs `swift --version` to check what it installed, before the links
  # can be laid in a directory that does not exist yet: for that one run they
  # sit in a temporary directory.
  aliases="$(mktemp -d)"
  alias_ncurses "$aliases"
  LD_LIBRARY_PATH="$aliases" mise use -g "swift@$version"
  rm -rf "$aliases"
  alias_ncurses "$(swift_lib_dir)"
  log "swift is ready: $(mise x swift -- swift --version 2>&1 | head -n 1)"
  log "swift package init --type executable, then swift run"
}

uninstall() {
  unuse swift
  dev-box-pkg drop libxml2-legacy
  log "~/.swiftpm and ~/.cache/org.swift.swiftpm are left in place."
}
