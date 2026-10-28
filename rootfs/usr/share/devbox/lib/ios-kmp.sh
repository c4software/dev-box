# shellcheck shell=bash
# dev-box: the iOS framework of a Kotlin Multiplatform project, linked on
# Linux. Sourced by dev-box-ios for `devbox ios kmp`, not run.
#
# Gradle never links an Apple framework on Linux: Kotlin/Native turns Apple
# targets down when the host is not a Mac, and the link task is skipped. The
# klibs build fine though, and the compiler itself can link them once it
# believes it runs on a Mac and finds the Apple parts it expects:
#   - the iOS runtime of Kotlin/Native, which only its macOS distribution
#     carries: taken from Maven Central and added to a copy of the Linux one
#     (hard links, in ~/.cache/devbox-ios-kmp);
#   - LLVM and libffi for the host: the Linux ones, public, downloaded by the
#     compiler into its own data directory;
#   - the linker of Xcode: the ld64.lld of the SDK's toolset, the one swift
#     build uses for iOS (the Swift toolchain's has no iOS platform), behind a
#     wrapper named ld (lld picks its mode from the name it is called by);
#     and its libtool, for a static framework: llvm-libtool-darwin, which the
#     toolset ships as llvm-lib;
#   - the iOS SDK and the clang runtime: the ones the ios environment built
#     from the Xcode .xip (devbox ios sdk).
# KONAN_USE_INTERNAL_SERVER makes the compiler read the toolchain and the
# SDK from its properties instead of asking xcrun. With it, it looks for the
# Xcode parts JetBrains keeps on a server of its own, which is not public:
# they are declared already extracted in the data directory, so nothing is
# fetched. The build is optimized and carries no debug info, whatever the
# project asks: the Linux LLVM asserts on the debug info of Apple targets.
#
# What the framework is made of comes from the project itself, through the
# Gradle init script ios-kmp.init.gradle next to this file.
#
# It also runs as root (docker exec -u 0 from the host): with rootless Docker,
# root in the box is the user of the host, the only one that may write into a
# project mounted from it. It then takes the tools of the box's user (mise,
# java, swift, the ios environment and its SDK) and writes nothing in their
# home: Gradle, Kotlin/Native and this cache stay in root's.

IOS_KMP_INIT="${IOS_KMP_INIT:-/usr/share/devbox/lib/ios-kmp.init.gradle}"
IOS_KMP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/devbox-ios-kmp"
IOS_KMP_SDKS="${XDG_CONFIG_HOME:+$XDG_CONFIG_HOME/swiftpm/swift-sdks}"
IOS_KMP_SDKS="${IOS_KMP_SDKS:-$HOME/.swiftpm/swift-sdks}"

# Run as root: the mise, the ios environment and the SDK of the box's user
# (USER_NAME of the container). Sets OAD_DIR and INSTALL of dev-box-ios.
ios_kmp_root_env() {
  [ "$(id -u)" = 0 ] || return 0
  local home
  home="$(getent passwd "${USER_NAME:-dev}" | cut -d: -f6)"
  [ -n "$home" ] && [ "$home" != "$HOME" ] || return 0
  export MISE_DATA_DIR="${MISE_DATA_DIR:-$home/.local/share/mise}"
  export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-$home/.config/mise}"
  export MISE_GLOBAL_CONFIG_FILE="${MISE_GLOBAL_CONFIG_FILE:-$home/.config/mise/config.toml}"
  export PATH="$home/.local/share/mise/shims:$home/.local/bin:$PATH"
  IOS_KMP_SDKS="$home/.swiftpm/swift-sdks"
  # shellcheck disable=SC2034 # read by need_ios of dev-box-ios
  OAD_DIR="$home/.local/share/omarchy-apple-dev"
  # shellcheck disable=SC2034 # read by need_ios of dev-box-ios
  INSTALL="$home/.local/bin/install-toolchain.sh"
}

ios_kmp_usage() {
  cat <<'EOF'
Usage: devbox ios kmp [project dir] [--module :path] [--target ios_arm64|ios_simulator_arm64] [--out dir] [--dynamic]

Links the iOS framework a Kotlin Multiplatform project declares
(binaries.framework), on Linux, from the klibs Gradle builds. The project
dir defaults to the current one; --module picks one project of the build
(every one that declares a framework otherwise); --target defaults to
ios_arm64, a device; --out defaults to <module>/build/devbox-ios/<target>;
--dynamic links a dynamic framework even when the project declares a static
one: swift build in the box loads every member of a static archive
(-all_load, from the toolset), which the static framework of a Compose
Multiplatform app does not survive (Skia objects twice).
Needs the ios environment with its SDK (devbox ios sdk) and java (devbox
dev-env java). As root, it takes the tools of the box's user.
EOF
}

# Gradle name of a Kotlin/Native target, and the platform of its SDK.
ios_kmp_gradle_target() {
  case "$1" in
  ios_arm64) echo iosArm64 ;;
  ios_simulator_arm64) echo iosSimulatorArm64 ;;
  *) return 1 ;;
  esac
}

ios_kmp_platform() {
  case "$1" in
  ios_arm64) echo iPhoneOS ;;
  ios_simulator_arm64) echo iPhoneSimulator ;;
  esac
}

# A copy of the Linux distribution with the iOS runtime of the macOS one.
ios_kmp_distribution() {
  local version="$1" linux dist archive
  linux="$HOME/.konan/kotlin-native-prebuilt-linux-x86_64-$version"
  dist="$IOS_KMP_CACHE/kotlin-native-$version"
  if [ ! -d "$linux" ]; then
    err "Kotlin/Native $version is not in ~/.konan: Gradle downloads it on its first iOS build"
    return 1
  fi
  if [ -d "$dist/konan/targets/ios_arm64" ] && [ -d "$dist/konan/targets/ios_simulator_arm64" ]; then
    echo "$dist"
    return 0
  fi
  log "Kotlin/Native $version: the iOS runtime of its macOS distribution, from Maven Central (about 300 MB, once)" >&2
  mkdir -p "$IOS_KMP_CACHE"
  archive="$IOS_KMP_CACHE/kotlin-native-macos-$version.tar.gz"
  curl -fL --progress-bar -o "$archive" \
    "https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-native-prebuilt/$version/kotlin-native-prebuilt-$version-macos-x86_64.tar.gz"
  rm -rf "$dist"
  cp -al "$linux" "$dist"
  tar -xzf "$archive" --strip-components=1 -C "$dist" \
    "kotlin-native-prebuilt-macos-x86_64-$version/konan/targets/ios_arm64" \
    "kotlin-native-prebuilt-macos-x86_64-$version/konan/targets/ios_simulator_arm64"
  rm -f "$archive"
  echo "$dist"
}

# The data directory of the compiler: the Apple parts declared extracted.
ios_kmp_data() {
  local sdk="$1" bundle="$2" data toolchain dep
  toolchain="$IOS_KMP_CACHE/toolchain"
  mkdir -p "$toolchain/usr/bin"
  printf '#!/bin/sh\n# lld in its Mach-O mode (ld64): it picks the mode from the name it is called by\nexec %s "$@"\n' \
    "$bundle/toolset/bin/ld64.lld" >"$toolchain/usr/bin/ld"
  chmod +x "$toolchain/usr/bin/ld"
  # A static framework is archived by libtool: llvm-libtool-darwin, the llvm-lib of the toolset
  printf '#!/bin/sh\n# libtool of Xcode: llvm-libtool-darwin of the SDK toolset\nexec %s "$@"\n' \
    "$bundle/toolset/bin/llvm-lib" >"$toolchain/usr/bin/libtool"
  chmod +x "$toolchain/usr/bin/libtool"
  ln -sfn "$bundle/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib" "$toolchain/usr/lib"
  data="$IOS_KMP_CACHE/data"
  mkdir -p "$data/dependencies"
  ln -sfn "$toolchain" "$data/dependencies/devbox-ios-toolchain"
  ln -sfn "$sdk" "$data/dependencies/devbox-ios-sdk"
  touch "$data/dependencies/.extracted"
  for dep in devbox-ios-toolchain devbox-ios-sdk; do
    grep -qx "$dep" "$data/dependencies/.extracted" || echo "$dep" >>"$data/dependencies/.extracted"
  done
  echo "$data"
}

# Links one framework. $1: the dump of devboxIosFrameworks for one project.
ios_kmp_link() {
  local block="$1" target="$2" out="$3" dynamic="$4" version path build name static dist data sdk bundle props llvm ffi
  version="$(awk -F'\t' '$1 == "VERSION" { print $2 }' <<<"$block")"
  IFS=$'\t' read -r _ path build name static < <(grep $'^FRAMEWORK\t' <<<"$block")
  out="${out:-$build/devbox-ios/$target}"
  bundle="$IOS_KMP_SDKS/darwin.artifactbundle"
  sdk="$(find "$bundle/Developer/Platforms/$(ios_kmp_platform "$target").platform/Developer/SDKs" \
    -maxdepth 1 -name "$(ios_kmp_platform "$target")[0-9]*.sdk" 2>/dev/null | sort -V | tail -n 1)"
  if [ -z "$sdk" ]; then
    err "no $(ios_kmp_platform "$target") SDK in $bundle: devbox ios sdk first"
    return 1
  fi
  dist="$(ios_kmp_distribution "$version")"
  data="$(ios_kmp_data "$sdk" "$bundle")"
  props="$dist/konan/konan.properties"
  llvm="$(sed -n 's/^llvm\.linux_x64\.user *= *//p' "$props")"
  ffi="$(sed -n 's/^libffiDir\.linux_x64 *= *//p' "$props")"
  local overrides="llvmHome.macos_x64=$llvm;libffiDir.macos_x64=$ffi;dependencies.macos_x64=$llvm $ffi"
  overrides+=";dependencies.macos_x64-$target=;targetToolchain.macos_x64-$target=devbox-ios-toolchain"
  overrides+=";additionalToolsDir.macos_x64=devbox-ios-toolchain;targetSysRoot.$target=devbox-ios-sdk"

  # An exported library is a library too: given once, whichever line names it first
  local args=() line kind value
  local -A given=()
  while IFS=$'\t' read -r kind value; do
    case "$kind" in
    INCLUDE | LIBRARY | EXPORT)
      [ -n "${given[$value]:-}" ] || args+=(-library "$value")
      given[$value]=1
      ;;
    esac
    case "$kind" in
    INCLUDE) args+=("-Xinclude=$value") ;;
    EXPORT) args+=("-Xexport-library=$value") ;;
    ARG) args+=("$value") ;;
    LINKER) args+=(-linker-option "$value") ;;
    esac
  done <<<"$block"
  [ "$static" = true ] && [ "$dynamic" != true ] && args+=(-Xstatic-framework)

  log "$path: $name.framework for $target (Kotlin/Native $version, $(basename "$sdk"), several minutes)"
  mkdir -p "$out"
  rm -rf "${out:?}/$name.framework"
  if ! KONAN_USE_INTERNAL_SERVER=1 "$dist/bin/kotlinc-native" "-Dos.name=Mac OS X" -Dos.arch=x86_64 \
    "-Xoverride-konan-properties=$overrides" "-Xkonan-data-dir=$data" -opt -Xadd-light-debug=disable \
    -produce framework -target "$target" -module-name "$name" -o "$out/$name" "${args[@]}" >"$out/kotlinc.log" 2>&1; then
    grep -v '^[[:space:]]*at ' "$out/kotlinc.log" | grep -iE 'error|exception' | head -n 20 >&2
    err "the link failed, the whole output is in $out/kotlinc.log"
    return 1
  fi
  line="$(awk -F'\t' '$1 == "RESOURCES" { print $2 }' <<<"$block")"
  if [ -n "$line" ]; then
    rm -rf "$out/compose-resources"
    cp -r "$line" "$out/compose-resources"
    log "Compose resources: $out/compose-resources, to copy into the .app as compose-resources/"
  fi
  log "framework: $out/$name.framework"
}

ios_kmp() {
  local dir="." module="" target="ios_arm64" out="" dynamic=false gradle_target task dump block
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --module) module="${2:?--module needs a project path, like :shared}"; shift 2 ;;
    --target) target="${2:?--target needs ios_arm64 or ios_simulator_arm64}"; shift 2 ;;
    --out) out="${2:?--out needs a directory}"; shift 2 ;;
    --dynamic) dynamic=true; shift ;;
    -h | --help) ios_kmp_usage; return 0 ;;
    -*) err "unknown option $1"; ios_kmp_usage >&2; return 2 ;;
    *) dir="$1"; shift ;;
    esac
  done
  gradle_target="$(ios_kmp_gradle_target "$target")" || {
    err "unknown target $target: ios_arm64 or ios_simulator_arm64"
    return 2
  }
  [ -x "$dir/gradlew" ] || { err "$dir has no gradlew: give the root of a Gradle build"; return 1; }
  [ "$(uname -m)" = x86_64 ] || { err "linux x86_64 only, like the ios environment"; return 1; }
  if ! mise which java >/dev/null 2>&1; then
    err "Gradle needs a JDK: devbox dev-env java first"
    return 1
  fi
  dir="$(cd "$dir" && pwd)"
  task="${module:+$module:}devboxIosFrameworks"
  log "Gradle: the klibs of the iOS framework and what it exports ($gradle_target)"
  dump="$(cd "$dir" && ./gradlew -q --console=plain -I "$IOS_KMP_INIT" "-PdevboxIosTarget=$gradle_target" "$task")" || {
    err "Gradle failed, see above"
    return 1
  }
  if ! grep -q $'^FRAMEWORK\t' <<<"$dump"; then
    err "no framework declared for $gradle_target${module:+ in $module} (kotlin { $gradle_target { binaries.framework { } } })"
    return 1
  fi
  # One file a framework, from its VERSION line to the next one
  local blocks status=0
  blocks="$(mktemp -d)"
  awk -v dir="$blocks" '/^VERSION\t/ { n++ } n { print > (dir "/" n) }' <<<"$dump"
  for block in "$blocks"/*; do
    ios_kmp_link "$(cat "$block")" "$target" "$out" "$dynamic" || { status=1; break; }
  done
  rm -rf "$blocks"
  return "$status"
}
