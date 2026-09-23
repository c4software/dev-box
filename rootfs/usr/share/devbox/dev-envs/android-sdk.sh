# shellcheck shell=bash
# devbox dev-env android-sdk: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Android SDK to build apps: cmdline-tools, platform-tools, platform, build-tools

cmdline-tools come from the mise registry (android-sdk), pinned to the version
of the day: mise sets ANDROID_HOME to that install, and sdkmanager lays the
platform-tools, the newest stable platform and build-tools inside it, so a
`devbox update tools` does not move the SDK. Run this again to add the newest
platform. The Android licenses are accepted on your behalf. Needs a JDK 17 or
21: java@temurin-21 when no java is declared yet, the declared one otherwise.
No emulator (no KVM, no display): deploy to a device over USB or `adb
connect`. linux x86_64 only, Google publishes no arm64 build-tools. A removal
deletes the SDK and its packages; java, ~/.android and ~/.gradle stay. The
lighter `android` environment (adb, fastboot only) is not needed next to it.
TXT
}

# The SDK is a mise install: its directory is ANDROID_HOME.
sdk_root() { mise where android-sdk; }

# Newest numeric entry of `sdkmanager --list` for a prefix (platforms;android-,
# build-tools;), previews and release candidates left out.
newest() {
  mise x android-sdk -- sdkmanager --list 2>/dev/null |
    awk -F'|' '{gsub(/ /, "", $1); print $1}' |
    grep -E "^$1[0-9]+(\.[0-9]+)*$" | sort -uV | tail -n 1 || true
}

is_supported() {
  [ "$(uname -m)" = "x86_64" ] && return 0
  echo "Google publishes the Android build-tools for linux x86_64 only, adb and fastboot through devbox pkg add android-tools"
  return 1
}

install() {

  # sdkmanager and Gradle need a JDK 17 or 21. A java the user declared is
  # kept; a newer one than 21 may be too recent for the Gradle of a project.
  if declared java; then
    log "java already declared: $(mise x java -- java -version 2>&1 | head -n 1)"
  else
    mise use -g java@temurin-21
  fi
  local major
  major="$(mise x java -- java -version 2>&1 | sed -nE '1s/.*version "([0-9]+).*/\1/p')"
  if [ -n "$major" ] && [ "$major" -gt 21 ]; then
    log "java $major is newer than what Gradle projects usually support: mise use -g java@temurin-21 if a build complains."
  fi

  # Pinned to the version of the day: `mise upgrade` leaves an exact version
  # alone, so the SDK packages below stay where they are.
  if declared android-sdk; then
    log "cmdline-tools already declared: $(mise current android-sdk)"
  else
    mise use -g "android-sdk@$(mise latest android-sdk)"
  fi

  local platform build_tools
  platform="$(newest 'platforms;android-')"
  build_tools="$(newest 'build-tools;')"
  [ -n "$platform" ] && [ -n "$build_tools" ] || {
    err "sdkmanager --list gave no platform or build-tools, is the network there?"
    return 1
  }
  log "accepting the Android SDK licenses"
  yes | mise x android-sdk -- sdkmanager --licenses >/dev/null || true
  mise x android-sdk -- sdkmanager "platform-tools" "$platform" "$build_tools"

  # Same as the android environment: platform-tools ships an old sqlite3, and
  # mise puts that directory on the PATH ahead of /usr/bin.
  local root
  root="$(sdk_root)"
  if [ -e "$root/platform-tools/sqlite3" ]; then
    rm -f "$root/platform-tools/sqlite3"
    log "sqlite3 from platform-tools removed: /usr/bin/sqlite3 stays the one on PATH"
  fi
  log "the Android SDK is ready in $root (ANDROID_HOME): $platform, $build_tools"
}

uninstall() {
  unuse android-sdk
  log "java stays: devbox dev-env --remove java. ~/.android and ~/.gradle are left in place."
}
