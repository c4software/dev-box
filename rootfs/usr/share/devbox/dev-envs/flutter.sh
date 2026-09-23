# shellcheck shell=bash
# devbox dev-env flutter: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Flutter + Dart, Android and web targets

Needs android-sdk (and its JDK), installed first. flutter@latest comes from
the mise registry, the official stable archive; the engine artifacts for
Android and the web are fetched at install. Linux desktop is turned off, so
`flutter doctor` does not ask for a GTK toolchain. The web runs without a
browser: `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080`,
then open the box's address. Browser tests want Chromium: devbox dev-env
browser, then CHROME_EXECUTABLE=chromium. linux x86_64 only. A removal takes
out flutter only: android-sdk stays, and ~/.pub-cache and ~/.config/flutter
are left in place.
TXT
}

is_supported() {
  [ "$(uname -m)" = "x86_64" ] && return 0
  echo "Flutter publishes no linux arm64 SDK, and the Android build-tools are x86_64 only"
  return 1
}

install() {
  dev_env install android-sdk
  mise use -g flutter@latest
  mise x flutter -- flutter config --no-enable-linux-desktop >/dev/null
  mise x flutter -- flutter precache --android --web
  # doctor lists what is still missing (a device, Chrome); it is information,
  # not a failure of the install.
  mise x flutter -- flutter doctor || true
  log "flutter is ready: flutter create my_app, then flutter build apk or flutter build web"
}

uninstall() {
  unuse flutter
  log "android-sdk stays: devbox dev-env --remove android-sdk."
  log "~/.pub-cache and ~/.config/flutter are left in place."
}
