# shellcheck shell=bash
# devbox dev-env android-sdk: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Android SDK and Android CLI to build apps: platform-tools, platform, build-tools

cmdline-tools come from the mise registry (android-sdk), pinned to the version
of the day: mise sets ANDROID_HOME to that install. They carry the Android CLI
(`android`, https://developer.android.com/tools/agents), which lays the
platform-tools, the newest stable platform and build-tools inside it, so a
`devbox update tools` does not move the SDK. Run this again to add the newest
platform. `android create`, `build`, `run`, `layout`, `preview` and `docs` are
there for you and for coding agents: `android init` lays its android-cli skill
for Claude Code, Codex and pi, linked for omp too. The CLI sends usage metrics
to Google unless --no-metrics is given (a --no-metrics line in ~/.androidrc
applies it to every call). Needs a JDK 17 or 21: java@temurin-21 when no java
is declared yet, the declared one otherwise. No emulator (no KVM, no
display): deploy to a device over USB or `adb connect`. linux x86_64 only,
Google publishes no arm64 build-tools. A removal deletes the SDK, its packages,
the android-cli skill and ~/.android/cli; java, the rest of ~/.android and
~/.gradle stay. The lighter `android` environment (adb, fastboot only) is not
needed next to it.
TXT
}

# The SDK is a mise install: its directory is ANDROID_HOME.
sdk_root() { mise where android-sdk; }

# The Android CLI of the declared cmdline-tools: absent from the ones older
# than 23.0, which only had the sdkmanager it replaces.
android_cli() {
  local cli
  cli="$(sdk_root)/cmdline-tools/$(mise current android-sdk)/bin/android"
  [ -x "$cli" ] && echo "$cli"
}

# Newest stable entry of `android sdk list --all` for a prefix (platforms/android-,
# build-tools/), betas and release candidates left out.
newest() {
  "$1" sdk list --all 2>/dev/null |
    awk '{print $1}' |
    grep -E "^$2[0-9]+(\.[0-9]+)*$" | sort -uV | tail -n 1 || true
}

# android init knows Claude Code, Codex and pi, not omp: the skill is linked
# there, as the devbox skill is.
OMP_SKILL="$HOME/.omp/agent/skills/android-cli"

is_supported() {
  [ "$(uname -m)" = "x86_64" ] && return 0
  echo "Google publishes the Android build-tools for linux x86_64 only, adb and fastboot through devbox pkg add android-tools"
  return 1
}

install() {

  # Gradle needs a JDK 17 or 21. A java the user declared is kept; a newer one
  # than 21 may be too recent for the Gradle of a project.
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
  # alone, so the SDK packages below stay where they are. A pin from before the
  # Android CLI is moved to the version of the day, and ANDROID_HOME with it.
  if declared android-sdk && [ -n "$(android_cli)" ]; then
    log "cmdline-tools already declared: $(mise current android-sdk)"
  else
    declared android-sdk && log "cmdline-tools $(mise current android-sdk) have no Android CLI: moving to the version of the day, the SDK packages are laid again (mise prune android-sdk frees the old one)"
    mise use -g "android-sdk@$(mise latest android-sdk)"
  fi

  local cli platform build_tools
  cli="$(android_cli)" || {
    err "no Android CLI in cmdline-tools $(mise current android-sdk)"
    return 1
  }
  platform="$(newest "$cli" 'platforms/android-')"
  build_tools="$(newest "$cli" 'build-tools/')"
  [ -n "$platform" ] && [ -n "$build_tools" ] || {
    err "android sdk list gave no platform or build-tools, is the network there?"
    return 1
  }
  # The Android CLI accepts the SDK license itself when it installs a package.
  "$cli" --sdk="$(sdk_root)" sdk install platform-tools "$platform" "$build_tools"

  # Same as the android environment: platform-tools ships an old sqlite3, and
  # mise puts that directory on the PATH ahead of /usr/bin.
  local root
  root="$(sdk_root)"
  if [ -e "$root/platform-tools/sqlite3" ]; then
    rm -f "$root/platform-tools/sqlite3"
    log "sqlite3 from platform-tools removed: /usr/bin/sqlite3 stays the one on PATH"
  fi
  log "the Android SDK is ready in $root (ANDROID_HOME): ${platform#*/}, ${build_tools#*/}"

  mise x android-sdk -- android init
  if [ -d "$HOME/.claude/skills/android-cli" ] && [ -d "${OMP_SKILL%/*}" ] && [ ! -e "$OMP_SKILL" ]; then
    ln -s "$HOME/.claude/skills/android-cli" "$OMP_SKILL"
    log "android-cli skill linked for omp"
  fi
  log "Android CLI $(mise x android-sdk -- android --version 2>/dev/null | tail -n 1): android --help, android skills list for the other skills"
}

uninstall() {
  if declared android-sdk && [ -n "$(android_cli)" ]; then
    "$(android_cli)" skills remove android-cli || true
  fi
  if [ -L "$OMP_SKILL" ]; then rm -f "$OMP_SKILL"; fi
  unuse android-sdk
  rm -rf "$HOME/.android/cli" "$HOME/.android/bin/android-cli"
  rmdir "$HOME/.android/bin" 2>/dev/null || true
  log "java stays: devbox dev-env --remove java. The rest of ~/.android (adb keys, debug.keystore) and ~/.gradle are left in place, so are the skills added with android skills add."
}
