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
it starts: turning it off is refused inside a container. What is left to you, once, because it takes your Apple
account:
  xtool setup          sign in, and build the iOS SDK from an Xcode.xip
The Xcode.xip comes from developer.apple.com, and its version must be the one
that carries this Swift. There is no simulator: an app runs on a real device,
paired over USB once (the USB block of compose.override.example.yaml, then
`devbox pkg add usbmuxd` and `sudo usbmuxd`), then reached over the network. linux x86_64 only. A removal
takes out xtool, pymobiledevice3 and the Python of lldb, and leaves swift,
python, the SDK in ~/.swiftpm and what xtool setup stored in place.
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
  log "next, once: xtool setup (your Apple account, and an Xcode.xip from developer.apple.com)"
  log "then: xtool new MyApp, cd MyApp, xtool dev build"
}

uninstall() {
  take_lldb_python
  unuse "$XTOOL" pypi:pymobiledevice3 "$LLDB_PYTHON"
  mise unset -g APPIMAGE_EXTRACT_AND_RUN
  log "swift and python stay: devbox dev-env --remove swift python."
  log "the iOS SDK (~/.swiftpm) and what xtool setup stored are left in place."
}
