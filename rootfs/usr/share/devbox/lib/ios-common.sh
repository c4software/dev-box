# shellcheck shell=bash
# dev-box: what devbox ios kmp and devbox ios xcode share. Sourced by
# ios-kmp.sh and ios-xcode.sh, not run. Uses log and err of dev-box-ios.
#
# It leans on omarchy-apple-dev as far as it goes: ship.sh --device builds an
# xtool package the way Xcode lays an app out (app icon, resources at the root
# of the .app, the app's Info.plist keys in its resource bundle), provision-dev.py and sign-dev.sh sign it for the device
# plugged in, pymobiledevice3 installs and launches it, over USB or, on iOS 27,
# over Wi-Fi through the tunnel of tools/tailnet-tunnel.py. What is left here:
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
#   - usbmuxd started, and restarted once when a device was plugged again;
#   - over Wi-Fi (IOS_WIFI, the address of the device), one tunnel opened for
#     the whole command and closed when it ends, every pymobiledevice3 call
#     sent through it (--rsd) instead of usbmuxd (--udid).

IOS_USER_HOME="$HOME"
# The address of the device over Wi-Fi (its tailnet address, or one the box
# routes to): empty, the device is on USB.
IOS_WIFI="${IOS_WIFI:-}"
# Set by ios_connect: the UDID of the device, and how pymobiledevice3 reaches
# it, for lockdown services (IOS_DEV) and the developer ones (IOS_DVT, its
# own userspace tunnel over USB, as before).
IOS_UDID_FOUND=""
IOS_DEV=()
IOS_DVT=()
IOS_TUNNEL_PID=""
# Where tools/tailnet-tunnel.py pair writes the RemotePairing records.
IOS_RP_RECORDS=".local/share/pymobiledevice3"

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
  for pair in .swiftpm/swift-sdks .config/xtool .appstoreconnect pymobile3-venv "$IOS_RP_RECORDS"; do
    [ -e "$home/$pair" ] || continue
    [ "$(readlink "$HOME/$pair" 2>/dev/null)" = "$home/$pair" ] && continue
    mkdir -p "$(dirname "$HOME/$pair")"
    rm -rf "${HOME:?}/$pair"
    ln -s "$home/$pair" "$HOME/$pair"
  done
  # Projects mounted from the host belong to another user: git reads them anyway.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
}

# The app of the xtool package in $1 built by ship.sh --device in the
# configuration $2 (debug or release), unsigned, at <pkg>/xtool/<product>.app.
ios_ship_build() {
  local pkg="$1" config="$2" product app
  product="$(sed -n 's/^product: *//p' "$pkg/xtool.yml")"
  (cd "$pkg" && ulimit -n 65536 && CONFIGURATION="$config" ship.sh --device 2>&1 | cat)
  app="$pkg/xtool/$product.app"
  [ -x "$app/$product" ] || ios_die "no app built: $app"
  [ -z "${IOS_APP_HOOK:-}" ] || "$IOS_APP_HOOK" "$app"
}

# As root when the box is run as root, through sudo otherwise.
ios_root() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
}

# The UDID of the device plugged in. usbmuxd started when it is not running,
# restarted once when it no longer sees a device that was plugged again.
# xtool devices waits for a device forever: 15 seconds at most, each time.
ios_usb_device() {
  local udid
  pgrep -x usbmuxd >/dev/null || ios_root usbmuxd
  udid="$(timeout 15 xtool devices 2>&1 | sed -n 's/.*\[usb\]: *//p' | head -n 1)"
  if [ -z "$udid" ]; then
    log "no device seen: usbmuxd restarted" >&2
    ios_root pkill -x usbmuxd || true
    sleep 2
    ios_root usbmuxd
    sleep 3
    udid="$(timeout 15 xtool devices 2>&1 | sed -n 's/.*\[usb\]: *//p' | head -n 1)"
  fi
  [ -n "$udid" ] || ios_die "no device over USB: plugged in, unlocked, trusted (devbox help ios, step 2), or over Wi-Fi with --wifi (devbox help ios-wifi)"
  echo "$udid"
}

# The UDIDs of the devices paired for Wi-Fi, one a line.
ios_wifi_records() {
  find "$IOS_USER_HOME/$IOS_RP_RECORDS" -maxdepth 1 -name 'remote_*.plist' -printf '%f\n' 2>/dev/null |
    sed 's/^remote_//; s/\.plist$//' | sort
}

# The tunnel of tools/tailnet-tunnel.py to the device at IOS_WIFI, held until
# the command ends. It needs root for its TUN device (sudo -n, the box's user
# has it) and the RemotePairing record of devbox ios pair; IOS_UDID picks one
# when several devices are paired.
ios_wifi_tunnel() {
  local udid="${IOS_UDID:-}" records out host port _
  records="$(ios_wifi_records)"
  if [ -z "$udid" ]; then
    [ -n "$records" ] || ios_die "no device paired for Wi-Fi: devbox ios pair, on USB, once (devbox help ios-wifi)"
    [ "$(wc -l <<<"$records")" -eq 1 ] || ios_die "several devices paired for Wi-Fi, pick one with IOS_UDID: $(paste -sd' ' <<<"$records")"
    udid="$records"
  fi
  grep -qx "$udid" <<<"$records" || ios_die "$udid is not paired for Wi-Fi: devbox ios pair, on USB"
  [ -e /dev/net/tun ] || ios_die "no /dev/net/tun in the box: the devices block of compose.yaml gives it"
  log "Wi-Fi tunnel to $udid at $IOS_WIFI" >&2
  out="$(mktemp)"
  "$IOS_USER_HOME/pymobile3-venv/bin/python" "$OAD_DIR/tools/tailnet-tunnel.py" "$IOS_WIFI" --udid "$udid" </dev/null >"$out" 2>&1 &
  IOS_TUNNEL_PID=$!
  trap ios_wifi_close EXIT
  for _ in $(seq 60); do
    grep -q '^RSD ' "$out" && break
    kill -0 "$IOS_TUNNEL_PID" 2>/dev/null || break
    sleep 1
  done
  read -r _ host port < <(grep '^RSD ' "$out") || {
    cat "$out" >&2
    rm -f "$out"
    ios_die "no tunnel to $IOS_WIFI: Wi-Fi on, unlocked, iOS 27, reachable from the box (devbox help ios-wifi)"
  }
  rm -f "$out"
  IOS_UDID_FOUND="$udid"
  IOS_DEV=(--rsd "$host" "$port")
  IOS_DVT=("${IOS_DEV[@]}")
}

# The tunnel stopped: sudo hands the signal to tailnet-tunnel.py.
ios_wifi_close() {
  [ -z "$IOS_TUNNEL_PID" ] || kill "$IOS_TUNNEL_PID" 2>/dev/null || true
  IOS_TUNNEL_PID=""
}

# The device, once per command: IOS_UDID_FOUND, IOS_DEV and IOS_DVT.
ios_connect() {
  [ -z "$IOS_UDID_FOUND" ] || return 0
  if [ -n "$IOS_WIFI" ]; then
    ios_wifi_tunnel
  else
    IOS_UDID_FOUND="$(ios_usb_device)"
    IOS_DEV=(--udid "$IOS_UDID_FOUND")
    IOS_DVT=(--userspace --udid "$IOS_UDID_FOUND")
  fi
}

# The identifier and the executable ios_install recorded in $1: IOS_ID, IOS_PRODUCT.
ios_record() {
  [ -f "$1" ] || ios_die "not installed yet: the install step first"
  { read -r IOS_ID && read -r IOS_PRODUCT; } <"$1"
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

# The app of identifier $1 stopped when it runs (dvt pkill, as device-run.sh
# does). The developer disk image dvt needs is mounted first, once per start
# of the device.
ios_stop() {
  local id="$1"
  pymobiledevice3 mounter list "${IOS_DEV[@]}" 2>/dev/null | grep -qi personalized ||
    pymobiledevice3 mounter auto-mount "${IOS_DEV[@]}"
  pymobiledevice3 developer dvt pkill --bundle "$id" "${IOS_DVT[@]}"
}

# The unsigned app $1 signed for the device under the identifier $2
# (XTL-<team key>.<its own> when empty, like xtool, so it never replaces the
# App Store or TestFlight one; $4 appended to it, for two apps of one
# identifier side by side), then installed. Records the identifier and the
# executable into $3.
ios_install() {
  local src="$1" id="$2" record="$3" suffix="${4:-}" udid stage app product dev tools
  ios_connect
  udid="$IOS_UDID_FOUND"
  ios_api_key
  stage="$(mktemp -d)"
  cp -R "$src" "$stage/"
  app="$stage/$(basename "$src")"
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
  ios_stop "$id"
  log "installed on $udid${IOS_WIFI:+ over Wi-Fi}"
  pymobiledevice3 apps install "${IOS_DEV[@]}" "$stage/signed.ipa"
  rm -rf "$stage"
  printf '%s\n%s\n' "$id" "$product" >"$record"
}

# The app installed by ios_install (identifier and executable in $1), the
# running one stopped first.
ios_launch() {
  ios_record "$1"
  ios_connect
  ios_stop "$IOS_ID"
  log "launching $IOS_ID"
  pymobiledevice3 developer dvt launch "$IOS_ID" "${IOS_DVT[@]}"
}

ios_logs() {
  ios_record "$1"
  ios_connect
  pymobiledevice3 syslog live "${IOS_DEV[@]}" --process-name "$IOS_PRODUCT"
}

# devbox ios pair: the device on USB, a RemotePairing record written by
# tools/tailnet-tunnel.py pair, for Wi-Fi afterwards (iOS 27).
ios_pair() {
  local udid
  IOS_WIFI=""
  ios_connect
  udid="$IOS_UDID_FOUND"
  log "RemotePairing record for $udid (no prompt on the device, it is trusted already)"
  "$IOS_USER_HOME/pymobile3-venv/bin/python" "$OAD_DIR/tools/tailnet-tunnel.py" pair
  [ -f "$IOS_USER_HOME/$IOS_RP_RECORDS/remote_$udid.plist" ] ||
    ios_die "no record for $udid in ~/$IOS_RP_RECORDS: see the output above"
  log "paired: ~/$IOS_RP_RECORDS/remote_$udid.plist, a key, kept like an SSH key"
  log "next: the cable out, Wi-Fi on, then devbox ios xcode --wifi <its address> (devbox help ios-wifi)"
}
