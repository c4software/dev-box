# shellcheck shell=bash
# dev-box: what devbox ios kmp and devbox ios xcode share. Sourced by
# ios-kmp.sh and ios-xcode.sh, not run. Uses log and err of dev-box-ios.
#
# It leans on omarchy-apple-dev as far as it goes: ship.sh --device builds an
# xtool package the way Xcode lays an app out (app icon, resources at the root
# of the .app, the app's Info.plist keys in its resource bundle), provision-dev.py and sign-dev.sh sign it for the device
# plugged in, pymobiledevice3 installs and launches it. What is left here:
#   - running as root (docker exec -u 0 from the host): with rootless Docker,
#     root in the box is the user of the host, the only one that may write
#     into a project mounted from it. It then takes the tools of the box's
#     user (mise, java, swift, the ios environment) and, through links in
#     /root inside the container, its SDK, Apple sign-in and pymobile3-venv,
#     where swift, xtool and ship.sh of root look for them;
#   - the signature through provision-dev.py and sign-dev.sh of
#     omarchy-apple-dev rather than xtool install: the path these apps are
#     tested with (xtool install's profile held the first 20 devices of the
#     team only before xtool-org/xtool#430);
#   - the app stopped before an install or a launch over the open one, which
#     otherwise stays stuck on the device until it is closed by hand;
#   - usbmuxd started, and restarted once when a device was plugged again.

IOS_USER_HOME="$HOME"

ios_die() {
  err "$*"
  exit 1
}

# As root: the tools, SDK, sign-in and Python of the box's user (USER_NAME of
# the container). Sets OAD_DIR and INSTALL of dev-box-ios, and
# IOS_USER_HOME.
ios_root_env() {
  [ "$(id -u)" = 0 ] || return 0
  local home pair
  home="$(getent passwd "${USER_NAME:-dev}" | cut -d: -f6)"
  [ -n "$home" ] && [ "$home" != "$HOME" ] || return 0
  IOS_USER_HOME="$home"
  export MISE_DATA_DIR="${MISE_DATA_DIR:-$home/.local/share/mise}"
  export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-$home/.config/mise}"
  export MISE_GLOBAL_CONFIG_FILE="${MISE_GLOBAL_CONFIG_FILE:-$home/.config/mise/config.toml}"
  export PATH="$home/.local/share/mise/shims:$home/.local/bin:$PATH"
  # shellcheck disable=SC2034 # read by need_ios of dev-box-ios
  OAD_DIR="$home/.local/share/omarchy-apple-dev"
  # shellcheck disable=SC2034 # read by need_ios of dev-box-ios
  INSTALL="$home/.local/bin/install-toolchain.sh"
  for pair in .swiftpm/swift-sdks .config/xtool .appstoreconnect pymobile3-venv; do
    [ -e "$home/$pair" ] || continue
    [ "$(readlink "$HOME/$pair" 2>/dev/null)" = "$home/$pair" ] && continue
    mkdir -p "$(dirname "$HOME/$pair")"
    rm -rf "${HOME:?}/$pair"
    ln -s "$home/$pair" "$HOME/$pair"
  done
  # Projects mounted from the host belong to another user: git reads them anyway.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
}

# The xtool package in $1 built by ship.sh --device in the configuration $2
# (debug or release), then the .ipa $3, unsigned. Prints nothing else.
ios_ship_build() {
  local pkg="$1" config="$2" ipa="$3" product app stage
  product="$(sed -n 's/^product: *//p' "$pkg/xtool.yml")"
  (cd "$pkg" && ulimit -n 65536 && CONFIGURATION="$config" ship.sh --device 2>&1 | cat)
  app="$pkg/xtool/$product.app"
  [ -x "$app/$product" ] || ios_die "no app built: $app"
  [ -z "${IOS_APP_HOOK:-}" ] || "$IOS_APP_HOOK" "$app"
  stage="$(mktemp -d)"
  mkdir -p "$stage/Payload"
  cp -R "$app" "$stage/Payload/"
  rm -f "$ipa"
  (cd "$stage" && zip -qry "$ipa" Payload)
  rm -rf "$stage"
}

ios_usbmuxd() {
  if [ "$(id -u)" = 0 ]; then usbmuxd; else sudo usbmuxd; fi
}

# The UDID of the device plugged in. usbmuxd started when it is not running,
# restarted once when it no longer sees a device that was plugged again.
# xtool devices waits for a device forever: 15 seconds at most, each time.
ios_device() {
  local udid
  pgrep -x usbmuxd >/dev/null || ios_usbmuxd
  udid="$(timeout 15 xtool devices 2>&1 | sed -n 's/.*\[usb\]: *//p' | head -n 1)"
  if [ -z "$udid" ]; then
    log "no device seen: usbmuxd restarted" >&2
    if [ "$(id -u)" = 0 ]; then pkill -x usbmuxd || true; else sudo pkill -x usbmuxd || true; fi
    sleep 2
    ios_usbmuxd
    sleep 3
    udid="$(timeout 15 xtool devices 2>&1 | sed -n 's/.*\[usb\]: *//p' | head -n 1)"
  fi
  [ -n "$udid" ] || ios_die "no device over USB: plugged in, unlocked, trusted (devbox help ios, step 2)"
  echo "$udid"
}

# The API key xtool auth signed in with: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
ios_api_key() {
  local status key
  status="$(xtool auth status 2>&1 | cat)"
  export ASC_KEY_ID="${ASC_KEY_ID:-$(sed -n 's/.*ASC key ID: *//p' <<<"$status")}"
  export ASC_ISSUER_ID="${ASC_ISSUER_ID:-$(sed -n 's/.*Issuer ID: *//p' <<<"$status")}"
  [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ] ||
    ios_die "xtool is not signed in with an App Store Connect API key: xtool auth login --mode key"
  if [ -z "${ASC_KEY_PATH:-}" ]; then
    for key in "$IOS_USER_HOME"/.appstoreconnect/private_keys/AuthKey_"$ASC_KEY_ID".p8 \
      "$IOS_USER_HOME"/.appstoreconnect/AuthKey_"$ASC_KEY_ID".p8; do
      [ -f "$key" ] && ASC_KEY_PATH="$key" && break
    done
  fi
  export ASC_KEY_PATH
  [ -f "${ASC_KEY_PATH:-}" ] || ios_die "no key file AuthKey_$ASC_KEY_ID.p8 in ~/.appstoreconnect"
}

# The app stopped when it runs (process named after the executable). The
# developer disk image dvt needs is mounted first, once per start of the device.
ios_stop() {
  local udid="$1" product="$2" pid
  pymobiledevice3 mounter list --udid "$udid" 2>/dev/null | grep -qi personalized ||
    pymobiledevice3 mounter auto-mount --udid "$udid"
  for pid in $(pymobiledevice3 developer dvt proclist --userspace --udid "$udid" 2>/dev/null | python3 -c '
import json, sys
for p in json.load(sys.stdin):
    if p.get("name") == sys.argv[1]:
        print(p["pid"])' "$product"); do
    log "running one stopped (pid $pid)"
    pymobiledevice3 developer dvt kill "$pid" --userspace --udid "$udid"
  done
}

# The unsigned .ipa $1 signed for the device plugged in under the identifier
# $2 (XTL-<team key>.<its own> when empty, like xtool, so it never replaces
# the App Store or TestFlight one; $4 appended to it, for two apps of one
# identifier side by side), then installed. Prints the identifier into $3.
ios_install() {
  local ipa="$1" id="$2" record="$3" suffix="${4:-}" udid stage app product dev tools
  udid="$(ios_device)"
  ios_api_key
  stage="$(mktemp -d)"
  (cd "$stage" && unzip -q "$ipa")
  app="$(find "$stage/Payload" -maxdepth 1 -name '*.app' -print -quit)"
  product="$(basename "$app" .app)"
  if [ -z "$id" ]; then
    id="XTL-${ASC_ISSUER_ID:0:8}"
    id="${id^^}.$(python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["CFBundleIdentifier"])' "$app/Info.plist")$suffix"
  fi
  dev="$IOS_USER_HOME/.config/omarchy-apple-dev/development"
  tools="$OAD_DIR/tools"
  log "development profile for $id on $udid"
  "$IOS_USER_HOME/pymobile3-venv/bin/python3" "$tools/provision-dev.py" --bundle-id "$id" --udid "$udid" --out "$dev" |
    grep -v 'Entitlements' || true
  python3 -c 'import plistlib, sys
p = sys.argv[1]; d = plistlib.load(open(p, "rb")); d["CFBundleIdentifier"] = sys.argv[2]; plistlib.dump(d, open(p, "wb"))' \
    "$app/Info.plist" "$id"
  log "signed (rcodesign)"
  "$tools/sign-dev.sh" "$app" "$stage/signed.ipa" "$dev" | tail -n 1
  ios_stop "$udid" "$product"
  log "installed on $udid"
  pymobiledevice3 apps install --udid "$udid" "$stage/signed.ipa"
  rm -rf "$stage"
  printf '%s\n%s\n' "$id" "$product" >"$record"
}

# The app installed by ios_install (identifier and executable in $1), the
# running one stopped first.
ios_launch() {
  local record="$1" udid id product
  [ -f "$record" ] || ios_die "not installed yet: the install step first"
  { read -r id && read -r product; } <"$record"
  udid="$(ios_device)"
  ios_stop "$udid" "$product"
  log "launching $id"
  pymobiledevice3 developer dvt launch "$id" --userspace --udid "$udid"
}

ios_logs() {
  local record="$1" udid id product
  [ -f "$record" ] || ios_die "not installed yet: the install step first"
  { read -r id && read -r product; } <"$record"
  udid="$(ios_device)"
  pymobiledevice3 syslog live --udid "$udid" --process-name "$product"
}
