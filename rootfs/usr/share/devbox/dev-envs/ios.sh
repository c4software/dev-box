# shellcheck shell=bash
# devbox dev-env ios: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
iOS and iPadOS apps without a Mac: Swift + xtool + pymobiledevice3

Needs swift and python, installed first. xtool builds, signs and installs a
SwiftPM app for iPhone and iPad; it is an AppImage, taken from its GitHub
releases through mise, and the box has no FUSE to mount one, so
APPIMAGE_EXTRACT_AND_RUN=1 goes into the mise config with it. pymobiledevice3
(PyPI, through mise) talks to the device: logs, screenshots, the tunnel iOS 17
and later ask for. Both are updated by `devbox update tools`. lldb, which the
swift environment leaves unable to start, gets the Python 3.9 it was built
against: the standalone build mise itself uses for python, taken as a tool of
its own (http:lldb-python, no command on the PATH, the default python is left
alone), and lldb and lldb-dap are started through a launcher that points
PYTHONHOME at it. lldb also leaves address randomization on for the program
it starts: turning it off is refused inside a container. There is no
simulator: an app runs on a real device. linux x86_64 only. A removal takes
out xtool, pymobiledevice3 and the Python of lldb, and leaves swift, python,
the SDK in ~/.swiftpm and what xtool setup stored in place.

What is left to you:

TXT
  next_steps
}

# What the install cannot do, since it takes an Apple account, a download
# behind a login and a device: printed at the end of an install and by --info.
next_steps() {
  cat <<'TXT'
  1. The Apple account and the iOS SDK, once
     Download Xcode from https://developer.apple.com/download/all/?q=Xcode in
     a browser (the page asks for an Apple ID, a free one will do, and the
     file weighs several GB). Take the Xcode that carries the Swift of the
     box (`swift --version`). Put the .xip in the home of the box: ./data/home
     on the host, or scp. Then, in the box:
       xtool setup
     Login mode: 0, an API key, with a paid Apple Developer Program
     membership; 1, the password, with any Apple ID (email, password, the
     two-factor code), which goes through private Apple APIs, hence the
     throwaway Apple ID xtool suggests. Then the path of the .xip: xtool
     builds the SDK from it, which takes a while.
       swift sdk list        must answer darwin
     The .xip can be deleted afterwards.

  2. The device, once
     On the host, copy the USB block of compose.override.example.yaml into
     your compose.override.yaml, stop a usbmuxd running there (the device has
     one owner), then docker compose up -d. In the box:
       devbox pkg add usbmuxd
     Plug the iPhone or iPad in, unlock it, then:
       sudo usbmuxd          again after each restart of the box
       xtool devices         answer Trust on the device, then run it again

  3. A first app
       xtool new Hello
       cd Hello
       xtool dev             builds, signs, installs on the device
     The first build takes a few minutes, the next ones are quick. On the
     device, if asked: Settings, Privacy & Security, Developer Mode (it
     restarts), then xtool dev again. At the first launch of the app, on
     "Untrusted Developer": Settings, General, VPN & Device Management, your
     Apple ID, Trust. With a free account the signature lasts 7 days: xtool
     dev again renews it. The bundle ID is in xtool.yml.

  4. Around it
       xtool dev build                builds without installing
       pymobiledevice3 usbmux list    the devices usbmuxd sees
       pymobiledevice3 syslog live    the logs of the device
       lldb                           the debugger of the toolchain

  Steps 1 and 3 follow the documentation of xtool, the place to look when
  one of them has changed:
       https://github.com/xtool-org/xtool
       https://xtool.sh/documentation/xtool/installation-linux
       https://xtool.sh/tutorials/xtool/first-app
TXT
}

XTOOL="github:xtool-org/xtool"

# The Python lldb embeds: the last 3.9 of python-build-standalone, pinned with
# its sha256 (3.9 is past its end of life, there will be no other).
LLDB_PYTHON="http:lldb-python"
LLDB_PYTHON_VERSION="3.9.25"
LLDB_PYTHON_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20251031/cpython-3.9.25+20251031-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz"
LLDB_PYTHON_SHA256="fe04e8b27bd69ca2144fc542428f8b9b5287b6a2e45516a4acfe2c2bc3102773"

# lldb is linked against libpython3.9.so.1.0, and an embedded Python only
# finds its standard library through PYTHONHOME. The library is linked into
# the toolchain, next to liblldb; lldb and lldb-dap move aside (.real) behind
# a launcher that sets the variable for them alone: set for the whole box, it
# would break every other Python. mise only puts the swift* commands of the
# toolchain on the PATH: the two launchers are linked next to them.
# lldb turns address randomization off for the program it launches, through
# personality(2), which the seccomp profile of Docker refuses ("personality
# set failed"): its launcher leaves it on. lldb-dap takes no such option.
give_lldb_python() {
  local root toolchain home bin extra
  root="$(mise where swift)"
  toolchain="$root/usr"
  home="$(mise where "$LLDB_PYTHON")/python"
  ln -sf "$home/lib/libpython3.9.so.1.0" "$toolchain/lib/libpython3.9.so.1.0"
  for bin in lldb lldb-dap; do
    [ -e "$toolchain/bin/$bin.real" ] || mv "$toolchain/bin/$bin" "$toolchain/bin/$bin.real"
    extra=""
    [ "$bin" = lldb ] && extra=" -O 'settings set target.disable-aslr false'"
    printf '#!/bin/sh\n# dev-box (devbox dev-env ios): %s with the Python it embeds.\nPYTHONHOME=%s exec %s%s "$@"\n' \
      "$bin" "$home" "$toolchain/bin/$bin.real" "$extra" > "$toolchain/bin/$bin"
    chmod +x "$toolchain/bin/$bin"
    ln -sf "$toolchain/bin/$bin" "$root/bin/$bin"
  done
  mise reshim
}

take_lldb_python() {
  local root toolchain bin
  root="$(mise where swift 2>/dev/null)" || return 0
  toolchain="$root/usr"
  [ -d "$toolchain/bin" ] || return 0
  for bin in lldb lldb-dap; do
    rm -f "$root/bin/$bin"
    if [ -e "$toolchain/bin/$bin.real" ]; then
      mv -f "$toolchain/bin/$bin.real" "$toolchain/bin/$bin"
    fi
  done
  rm -f "$toolchain/lib/libpython3.9.so.1.0"
  mise reshim
}

is_installed() { declared "$XTOOL" && declared pypi:pymobiledevice3; }

is_supported() {
  [ "$(uname -m)" = "x86_64" ] && return 0
  echo "it sits on swift, which has only been made to run on Arch for x86_64"
  return 1
}

install() {
  dev_env install swift
  dev_env install python
  # bin=xtool: the release asset is xtool-x86_64.AppImage, the command is xtool.
  mise use -g "${XTOOL}[bin=xtool]@latest" pypi:pymobiledevice3@latest
  mise set -g APPIMAGE_EXTRACT_AND_RUN=1
  # bin_path names a directory the archive does not have: no python lands on
  # the PATH.
  mise use -g "${LLDB_PYTHON}[url=$LLDB_PYTHON_URL,checksum=sha256:$LLDB_PYTHON_SHA256,bin_path=share]@$LLDB_PYTHON_VERSION"
  give_lldb_python
  log "xtool $(mise x "$XTOOL" -- xtool --version 2>&1 | awk '{print $NF}'), pymobiledevice3 $(mise x pypi:pymobiledevice3 -- pymobiledevice3 version 2>&1 | tail -n 1)"
  log "$("$(mise where swift)/bin/lldb" --version 2>&1 | head -n 1)"
  log "ios is ready, three steps are left to you (devbox dev-env --info ios):"
  echo
  next_steps
}

uninstall() {
  take_lldb_python
  unuse "$XTOOL" pypi:pymobiledevice3 "$LLDB_PYTHON"
  mise unset -g APPIMAGE_EXTRACT_AND_RUN
  log "swift and python stay: devbox dev-env --remove swift python."
  log "the iOS SDK (~/.swiftpm) and what xtool setup stored are left in place."
}
