# shellcheck shell=bash
# dev-box: devbox ios ui, the app on the device driven from the box, the way a
# test or an agent checks a change on a real iPhone: WebDriverAgent (the
# XCUITest runner of Appium) answers on the device, its ports reach the box
# through usbmuxd, and ios-ui.py talks to it (taps, texts, screenshots, video).
# Sourced by dev-box-ios after ios-common.sh, not run.
#
# Kept between two commands, in <user's home>/.cache/dev-box/ios-ui: the
# identifier the runner was installed under (runner), the pids of the runner
# and of the port forwards (*.pid), their logs, and the WebDriverAgent session
# ios-ui.py opened (session).

IOS_UI_PORT="${IOS_UI_PORT:-8100}"
IOS_UI_MJPEG_PORT="${IOS_UI_MJPEG_PORT:-9100}"
IOS_UI_PY=/usr/share/devbox/lib/ios-ui.py

ios_ui_dir() {
  local dir="${IOS_USER_HOME:-$HOME}/.cache/dev-box/ios-ui"
  mkdir -p "$dir"
  ios_give_back "$dir"
  echo "$dir"
}

ios_ui_ready() {
  curl -fsS --max-time 5 "http://127.0.0.1:$IOS_UI_PORT/status" 2>/dev/null | grep -q '"ready" *: *true'
}

# The identifier of the runner on the device: the one ui install recorded,
# else the first app whose identifier ends in WebDriverAgentRunner.xctrunner
# (installed some other way).
ios_ui_runner() {
  local dir
  dir="$(ios_ui_dir)"
  if [ -n "${IOS_UI_RUNNER:-}" ]; then
    echo "$IOS_UI_RUNNER"
  elif [ -f "$dir/runner" ]; then
    head -n 1 "$dir/runner"
  else
    pymobiledevice3 apps list "${IOS_DEV[@]}" --type User 2>/dev/null | python3 -c '
import json, sys
try:
    apps = json.load(sys.stdin)
except ValueError:
    apps = {}
print(next((k for k in apps if k.endswith("WebDriverAgentRunner.xctrunner")), ""))'
  fi
}

# $1 started in the background, detached from this command (it outlives it),
# its pid in <dir>/$2.pid and its output in <dir>/$2.log.
ios_ui_spawn() {
  local name="$1" dir
  shift
  dir="$(ios_ui_dir)"
  setsid "$@" >"$dir/$name.log" 2>&1 </dev/null &
  echo $! >"$dir/$name.pid"
}

ios_ui_kill() {
  local dir pid
  dir="$(ios_ui_dir)"
  [ -f "$dir/$1.pid" ] || return 0
  pid="$(cat "$dir/$1.pid")"
  kill "$pid" 2>/dev/null || true
  rm -f "$dir/$1.pid"
}

# ui install <WebDriverAgentRunner-Runner.zip>: the runner of a release of
# https://github.com/appium/WebDriverAgent signed and installed like an app
# (ios_install: an API key, or the Apple ID password over USB).
ios_ui_install() {
  local zip="${1:-}" stage app dir
  [ -f "$zip" ] || ios_die "ui install <WebDriverAgentRunner-Runner.zip>: the runner for a real device, from a release of https://github.com/appium/WebDriverAgent (devbox help ios-ui, step 1)"
  stage="$(mktemp -d)"
  unzip -q "$zip" -d "$stage"
  app="$(find "$stage" -maxdepth 3 -name '*.app' -type d -print -quit)"
  [ -n "$app" ] || { rm -rf "$stage"; ios_die "no .app in $zip"; }
  dir="$(ios_ui_dir)"
  ios_install "$app" "" "$dir/runner"
  rm -rf "$stage"
  ios_give_back "$dir"
  log "next: devbox ios ui start"
}

# ui start: the runner launched (XCUITest, through the developer disk image),
# then its HTTP port and its MJPEG stream forwarded to 127.0.0.1 of the box.
# USB only: usbmuxd carries the forwards.
ios_ui_start() {
  local runner deadline
  if ios_ui_ready; then
    log "WebDriverAgent answers already on 127.0.0.1:$IOS_UI_PORT"
    return 0
  fi
  [ -z "$IOS_WIFI" ] || ios_die "ui: over USB only (the port forwards go through usbmuxd)"
  ios_connect
  runner="$(ios_ui_runner)"
  [ -n "$runner" ] || ios_die "no WebDriverAgent runner on the device: devbox ios ui install <WebDriverAgentRunner-Runner.zip> (devbox help ios-ui)"
  pymobiledevice3 mounter list "${IOS_DEV[@]}" 2>/dev/null | grep -qi personalized ||
    pymobiledevice3 mounter auto-mount "${IOS_DEV[@]}"
  ios_ui_stop quiet
  log "WebDriverAgent ($runner), then the ports $IOS_UI_PORT and $IOS_UI_MJPEG_PORT forwarded"
  ios_ui_spawn runner pymobiledevice3 developer dvt xcuitest "$runner" "${IOS_DVT[@]}"
  ios_ui_spawn forward pymobiledevice3 usbmux forward "$IOS_UI_PORT" "$IOS_UI_PORT" --serial "$IOS_UDID_FOUND"
  ios_ui_spawn mjpeg pymobiledevice3 usbmux forward "$IOS_UI_MJPEG_PORT" "$IOS_UI_MJPEG_PORT" --serial "$IOS_UDID_FOUND"
  deadline=$((SECONDS + 90))
  until ios_ui_ready; do
    [ "$SECONDS" -lt "$deadline" ] ||
      ios_die "WebDriverAgent does not answer after 90 s: device unlocked? $(ios_ui_dir)/runner.log"
    sleep 2
  done
  log "WebDriverAgent ready: devbox ios ui session <bundle id>, then labels, tap, shot (devbox help ios-ui)"
}

# ui stop: the runner and the forwards stopped. WebDriverAgent also listens on
# the local network of the device: not left running after the checks.
ios_ui_stop() {
  local name
  for name in mjpeg forward runner net; do ios_ui_kill "$name"; done
  [ "${1:-}" = quiet ] || log "WebDriverAgent and its port forwards stopped"
}

# ui net <condition>|off|list: a network condition of the device (Network
# Link Conditioner through DVT), held until ui net off or ui stop.
ios_ui_net() {
  local condition="${1:-list}"
  ios_connect
  case "$condition" in
  list) pymobiledevice3 developer dvt condition list "${IOS_DVT[@]}" | sed -n 's/.*"identifier": "\(SlowNetwork[^"]*\)".*/\1/p' ;;
  off)
    ios_ui_kill net
    log "network condition cleared"
    ;;
  *)
    ios_ui_kill net
    ios_ui_spawn net pymobiledevice3 developer dvt condition set "$condition" "${IOS_DVT[@]}"
    sleep 6
    log "network condition $condition (ui net off clears it)"
    ;;
  esac
}

# ui prefs <bundle id>: the preferences (UserDefaults) of a development app,
# as JSON; values holding JSON text are decoded. Read only: iOS keeps them in
# memory (cfprefsd) and writes them back over a file pushed in their place.
ios_ui_prefs() {
  local id="${1:?ui prefs <bundle id>}" out
  ios_connect
  out="$(mktemp -d)"
  pymobiledevice3 apps pull "${IOS_DEV[@]}" "$id" "/Library/Preferences/$id.plist" "$out/prefs.plist" >/dev/null ||
    ios_die "no preferences for $id (a development-signed app, launched once?)"
  python3 - "$out/prefs.plist" <<'PY'
import json, plistlib, sys

def decode(value):
    # Data holding text (an app storing JSON as Data) read as that text
    if isinstance(value, bytes):
        try:
            value = value.decode("utf-8")
        except UnicodeDecodeError:
            return value.hex()
    while isinstance(value, str) and value[:1] in "{[\"":
        try:
            value = json.loads(value)
        except ValueError:
            break
    if isinstance(value, dict):
        return {k: decode(v) for k, v in value.items()}
    if isinstance(value, list):
        return [decode(v) for v in value]
    return value

print(json.dumps(decode(plistlib.load(open(sys.argv[1], "rb"))), indent=2, default=str, ensure_ascii=False))
PY
  rm -rf "$out"
}

# ui crashes [name]: the crash reports on the device, newest last; with a
# name (the executable), only its own.
ios_ui_crashes() {
  ios_connect
  pymobiledevice3 crash ls "${IOS_DEV[@]}" 2>/dev/null | grep -i -- "${1:-.ips}" | sort
}

ios_ui() {
  local action="${1:-}"
  case "$action" in
  start) ios_ui_start ;;
  stop) ios_ui_stop ;;
  install)
    shift
    ios_ui_install "$@"
    ;;
  net)
    shift
    ios_ui_net "$@"
    ;;
  prefs)
    shift
    ios_ui_prefs "$@"
    ;;
  crashes)
    shift
    ios_ui_crashes "$@"
    ;;
  "" | -h | --help) python3 "$IOS_UI_PY" --help ;;
  *)
    ios_ui_ready || ios_die "WebDriverAgent does not answer on 127.0.0.1:$IOS_UI_PORT: devbox ios ui start"
    IOS_UI_DIR="$(ios_ui_dir)" python3 "$IOS_UI_PY" "$@"
    ;;
  esac
}
