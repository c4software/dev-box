# shellcheck shell=bash
# devbox dev-env android: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Android platform-tools (adb, fastboot), no SDK

Only the platform-tools zip Google publishes at a fixed URL: no SDK manager,
no platform, no Java. It goes through mise's http backend; the URL carries no
version, so `devbox update tools` cannot see a newer build: run this again to
refresh. linux x86_64 only: on arm64 use `devbox pkg add android-tools`. A
removal leaves ~/.android (adb keys, avd) in place. To build apps, take
android-sdk instead: it carries its own platform-tools.
TXT
}

is_installed() { declared "http:android-platform-tools"; }

# The platform-tools zip carries its own sqlite3, older than the one of the
# image, and mise's http backend exposes every binary of bin_path: the shim
# would shadow /usr/bin/sqlite3. Removing the binary from the install (rather
# than the shim, which every `mise reshim` recreates) keeps the Arch one first.
drop_android_sqlite3() {
  local dir="$HOME/.local/share/mise/installs/http-android-platform-tools/latest-linux/platform-tools"
  if [ -e "$dir/sqlite3" ]; then
    rm -f "$dir/sqlite3"
    mise reshim
    log "sqlite3 from platform-tools removed: /usr/bin/sqlite3 stays the one on PATH"
  fi
}

is_supported() {
  [ "$(uname -m)" = "x86_64" ] && return 0
  echo "Google publishes platform-tools for linux x86_64 only, use devbox pkg add android-tools"
  return 1
}

install() {
  local url="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
  mise install -f "http:android-platform-tools[url=$url,bin_path=platform-tools]@latest-linux"
  mise use -g "http:android-platform-tools[url=$url,bin_path=platform-tools]@latest-linux"
  drop_android_sqlite3
  log "adb and fastboot are ready: $(mise x http:android-platform-tools -- adb --version | sed -n '2p')"
}

uninstall() {
  unuse http:android-platform-tools
  log "~/.android (adb keys, avd) is left in place."
}
