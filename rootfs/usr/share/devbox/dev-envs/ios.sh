# shellcheck shell=bash
# devbox dev-env ios: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
iOS and iPadOS apps without a Mac: Swift + omarchy-apple-dev (xtool, pymobiledevice3)

Needs swift and python, installed first. The tools come from omarchy-apple-dev
(github.com/joshuaswarren/omarchy-apple-dev), cloned at a pinned release into
~/.local/share/omarchy-apple-dev, whose install-toolchain.sh runs in its
--user-only mode, on the Swift of mise. It builds xtool from source, with the
fixes not released upstream yet (a few minutes, the first time), and installs
rcodesign, ipsw and pymobiledevice3 (a venv in ~/pymobile3-venv). Once the
SDK is in, it adds what the SDK of xtool lacks: the SwiftData and #Predicate
macros, and Linux stand-ins for actool, ibtool, xcstringstool and momc, so
asset catalogs, storyboards and string catalogs build. Its scripts are on the
PATH: install-toolchain.sh, device-run.sh (build, install, launch, logs,
lldb, crash reports) and ship.sh (an App Store .ipa, TestFlight). Flutter
apps and the experimental mode without an Xcode download are in the clone.
libimobiledevice, which the xtool build links, comes through `devbox pkg`.
lldb, which the swift environment leaves unable to start, gets the Python 3.9
it was built against: the standalone build mise itself uses for python, taken
as a tool of its own (http:lldb-python, no command on the PATH, the default
python is left alone), and lldb and lldb-dap are started through a launcher
that points PYTHONHOME at it. lldb also leaves address randomization on for the program
it starts: turning it off is refused inside a container. There is no
simulator: an app runs on a real device. linux x86_64 only. Run it again
after an image update to move to the release the image pins. A removal takes
out the clone, xtool, rcodesign, ipsw, the venv and the Python of lldb, and
leaves swift, python, the SDK (~/.swiftpm/swift-sdks and its cache
~/.cache/xtool), the Apple sign-in of xtool (~/.local/share/xtool) and the
pairing records of pymobiledevice3 (~/.pymobiledevice3) in place.

What is left to you:

TXT
  next_steps
}

# What the install cannot do, since it takes an Apple account, a download
# behind a login and a device: printed at the end of an install and by --info.
# The text is the ios topic of `devbox help`, without its title.
IOS_HELP="/usr/share/devbox/help/ios.txt"

next_steps() {
  if [ -r "$IOS_HELP" ]; then
    tail -n +3 "$IOS_HELP"
  else
    echo "  $IOS_HELP is missing: devbox help ios cannot show the steps."
  fi
}

# omarchy-apple-dev, pinned: a newer release is a change of this line, tried
# in a throwaway box first.
OAD_REPO="https://github.com/joshuaswarren/omarchy-apple-dev"
OAD_TAG="v0.4.0"
OAD_DIR="$HOME/.local/share/omarchy-apple-dev"
OAD_BIN="$HOME/.local/bin"
# The scripts of the clone put on the PATH, through a wrapper each.
OAD_SCRIPTS=(install-toolchain.sh device-run.sh ship.sh)
# What install-toolchain.sh installs in the home.
OAD_VENV="$HOME/pymobile3-venv"
OAD_LIB="$HOME/.local/lib/omarchy-apple-dev"
OAD_CACHE="$HOME/.cache/omarchy-apple-dev"
# What the xtool build links, and the image does not have. The other tools
# install-toolchain.sh asks for come with the image: zip (with luarocks),
# heif-convert (libheif, with chafa), pdftocairo (poppler), cc and pkg-config.
OAD_PACKAGES=(libimobiledevice)
WRAPPER_MARK="# dev-box (devbox dev-env ios)"

# Before omarchy-apple-dev, the environment took xtool as an AppImage through
# mise, and pymobiledevice3 from PyPI: an install moves a box off them.
OLD_XTOOL="github:xtool-org/xtool"
OLD_PMD3="pypi:pymobiledevice3"

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

# The clone at OAD_TAG: cloned the first time, moved to the tag afterwards.
# A file of the clone changed by hand stops the move, git says which.
fetch_oad() {
  if [ -d "$OAD_DIR/.git" ]; then
    git -C "$OAD_DIR" fetch -q --depth 1 origin "refs/tags/$OAD_TAG:refs/tags/$OAD_TAG"
    git -C "$OAD_DIR" -c advice.detachedHead=false checkout -q "$OAD_TAG"
  else
    mkdir -p "$(dirname "$OAD_DIR")"
    git clone -q --depth 1 --branch "$OAD_TAG" -c advice.detachedHead=false "$OAD_REPO" "$OAD_DIR"
  fi
}

# The scripts read the toolchain from the real path of the swift on the PATH,
# where the box has mise shims: they run under `mise x`, which puts the swift
# and the python of mise there instead. The wrapper keeps $0 the path of the
# clone, where device-run.sh finds its tools. install-toolchain.sh always runs
# --user-only: its other mode installs swift-bin from the AUR, with sudo.
write_wrappers() {
  local name extra
  mkdir -p "$OAD_BIN"
  for name in "${OAD_SCRIPTS[@]}"; do
    extra=""
    [ "$name" = install-toolchain.sh ] && extra='
case " $* " in
*" --repair "* | *" --curses-compat "* | *" --mode-help "*) ;;
*) set -- --user-only "$@" ;;
esac'
    printf '#!/bin/sh\n%s: %s of %s.%s\nexec mise x swift python -- %s "$@"\n' \
      "$WRAPPER_MARK" "$name" "$OAD_DIR" "$extra" "$OAD_DIR/$name" > "$OAD_BIN/$name"
    chmod 755 "$OAD_BIN/$name"
  done
  ln -sfn "$OAD_VENV/bin/pymobiledevice3" "$OAD_BIN/pymobiledevice3"
}

remove_wrappers() {
  local name
  for name in "${OAD_SCRIPTS[@]}"; do
    if grep -qF "$WRAPPER_MARK" "$OAD_BIN/$name" 2>/dev/null; then
      rm -f "$OAD_BIN/$name"
    fi
  done
  if [ "$(readlink "$OAD_BIN/pymobiledevice3" 2>/dev/null)" = "$OAD_VENV/bin/pymobiledevice3" ]; then
    rm -f "$OAD_BIN/pymobiledevice3"
  fi
}

darwin_sdk() { mise x swift -- swift sdk list 2>/dev/null | grep -qx darwin; }

is_installed() { [ -d "$OAD_DIR/.git" ] || declared "$OLD_XTOOL"; }

is_supported() {
  [ "$(uname -m)" = "x86_64" ] && return 0
  echo "it sits on swift, which has only been made to run on Arch for x86_64"
  return 1
}

install() {
  dev_env install swift
  dev_env install python
  dev-box-pkg add "${OAD_PACKAGES[@]}"
  if declared "$OLD_XTOOL" || declared "$OLD_PMD3"; then
    log "the xtool AppImage and pymobiledevice3 of mise make way for omarchy-apple-dev"
    unuse "$OLD_XTOOL" "$OLD_PMD3"
  fi
  mise unset -g APPIMAGE_EXTRACT_AND_RUN 2>/dev/null || true
  # bin_path names a directory the archive does not have: no python lands on
  # the PATH.
  mise use -g "${LLDB_PYTHON}[url=$LLDB_PYTHON_URL,checksum=sha256:$LLDB_PYTHON_SHA256,bin_path=share]@$LLDB_PYTHON_VERSION"
  give_lldb_python
  log "omarchy-apple-dev $OAD_TAG in $OAD_DIR"
  fetch_oad
  write_wrappers
  # Without an SDK, install-toolchain.sh stops at it with exit 1, after
  # xtool, rcodesign, ipsw and the venv: the SDK is the first step left to the
  # user. Its standard input is closed, so it asks nothing: the mode is the
  # one chosen last time, full otherwise.
  log "install-toolchain.sh --user-only (building xtool takes a few minutes the first time)"
  local rc=0
  "$OAD_BIN/install-toolchain.sh" </dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -x "$OAD_BIN/xtool" ] && [ -x "$OAD_VENV/bin/pymobiledevice3" ] && ! darwin_sdk; then
      log "install-toolchain.sh stopped at the SDK, as expected: step 1 below. Run it as"
      log "install-toolchain.sh, from the PATH, not by the path it printed: that one"
      log "would install swift-bin with pacman and yay instead of using the Swift of mise."
    else
      err "install-toolchain.sh failed (exit $rc), see its output above"
      return 1
    fi
  fi
  log "xtool $("$OAD_BIN/xtool" --version 2>&1 | awk '{print $NF}'), pymobiledevice3 $("$OAD_VENV/bin/pymobiledevice3" version 2>&1 | tail -n 1)"
  log "$("$(mise where swift)/bin/lldb" --version 2>&1 | head -n 1)"
  if darwin_sdk; then
    log "ios is ready, the SDK is in; what is left to you (shown again by devbox help ios):"
  else
    log "ios is ready, the steps left to you (shown again by devbox help ios):"
  fi
  echo
  next_steps
}

uninstall() {
  take_lldb_python
  unuse "$OLD_XTOOL" "$OLD_PMD3" "$LLDB_PYTHON"
  mise unset -g APPIMAGE_EXTRACT_AND_RUN 2>/dev/null || true
  remove_wrappers
  # What install-toolchain.sh installed: xtool is a link into OAD_LIB.
  case "$(readlink "$OAD_BIN/xtool" 2>/dev/null)" in
  "$OAD_LIB"/*) rm -f "$OAD_BIN/xtool" ;;
  esac
  rm -f "$OAD_BIN/rcodesign" "$OAD_BIN/ipsw"
  rm -rf "$OAD_DIR" "$OAD_LIB" "$OAD_CACHE" "$OAD_VENV"
  dev-box-pkg drop "${OAD_PACKAGES[@]}"
  log "swift and python stay: devbox dev-env --remove swift python."
  log "left in place: the iOS SDK (~/.swiftpm/swift-sdks) and its cache (~/.cache/xtool),"
  log "the Apple sign-in of xtool (~/.local/share/xtool), the pairing records of"
  log "pymobiledevice3 (~/.pymobiledevice3)."
}
