# shellcheck shell=bash
# dev-box: an iOS app of an Xcode project (or an XcodeGen project.yml, or
# around the framework of a Kotlin Multiplatform build) built, signed,
# installed and launched on Linux. Sourced by dev-box-ios for
# `devbox ios xcode`, not run. Uses log and err of dev-box-ios.
#
# omarchy-apple-dev does the work: xcodeproj2xtool.py turns the app target
# into an xtool package, in the configuration asked for (Debug by default),
# with the SwiftUI and UIKit shortcuts of the asset symbols (Color.name,
# UIColor(.name)) when the project has them on; tools/host-manifests.py
# answers as on a Mac the manifests of direct dependencies that test the
# build machine (RxSwift leaves RxCocoa out on Linux); kmp/build-framework.sh
# links the framework of a Kotlin Multiplatform build; ios-common.sh builds
# the package through ship.sh --device, signs, installs and launches it.
# What is left here, each part found on a real app (SwiftUI, Firebase,
# RxSwift, a private package, a Compose Multiplatform app):
#   - a project.yml generated into an .xcodeproj by XcodeGen, built once from
#     its sources into the cache; the files it writes next to the sources are
#     removed once the package is generated;
#   - dependencies taken from a local git copy (--package);
#   - iOS 17 at least: the asset symbols of the box's actool need it;
#   - with --kmp, the .xcframework of that framework taken as a binary target
#     of the package (the generator drops OTHER_LDFLAGS and
#     FRAMEWORK_SEARCH_PATHS), and its Compose resources put into the .app.

# shellcheck source=/usr/share/devbox/lib/ios-kmp.sh
. /usr/share/devbox/lib/ios-kmp.sh

IOS_XCODE_PY="${IOS_XCODE_PY:-/usr/share/devbox/lib/ios-xcode.py}"
IOS_XCODE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/devbox-ios-xcode"
IOS_XCODEGEN_VERSION="${IOS_XCODEGEN_VERSION:-2.44.1}"

ios_xcode_usage() {
  cat <<'EOF'
Usage: devbox ios xcode [project dir] [step] [options]

Builds the app of an Xcode project on Linux, then installs and launches it
on the iPhone or iPad plugged in, or over Wi-Fi with --wifi. The project is
the .xcodeproj of the dir, or its project.yml (XcodeGen). Steps:
  run       build, install and launch (the default)
  project   the xtool package generated from the project
  build     the app, unsigned (<out>/xtool/xtool/<Product>.app)
  install   signed for the device, then installed
  launch    launched, the running one stopped first
  logs      the logs of the app on the device

Options:
  --project path             the .xcodeproj or project.yml (the only one in
                             the dir otherwise)
  --target name              the app target (when the project has several)
  --configuration name       the build configuration (Debug)
  --package name=path[@ref]  a dependency taken from a local git copy, at
                             the commit of ref (its current one otherwise),
                             in place of the one the project names (a
                             private repository, a branch not pushed yet)
  --kmp :module              the app links the framework of that Gradle
                             project (Kotlin Multiplatform), from the
                             nearest dir above with a gradlew: linked first
                             (kmp/build-framework.sh of omarchy-apple-dev),
                             embedded with its Compose resources. Needs java
                             and, for a build with Android targets, the
                             Android SDK of sdk.dir
  --signed-id id             the identifier the app is signed under
                             (XTL-<team key>.<identifier>, like xtool, so it
                             never replaces the App Store or TestFlight one)
  --signed-suffix suffix     appended to that default identifier, for two
                             apps of one identifier on the device (.kmp)
  --out dir                  where it all goes (<dir>/build/devbox-ios)
  --wifi address             the device over Wi-Fi rather than USB, at its
                             tailnet address or one the box routes to:
                             iOS 27, paired once with devbox ios pair
                             (devbox help ios-wifi)

Customizing:
  The package xcodeproj2xtool.py of omarchy-apple-dev generates (settings of
  the configuration, asset symbol shortcuts as the project's
  ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS says) is built
  by its ship.sh --device (app icon, resources at the root of the .app, the
  app's Info.plist keys in the resource bundle; its variables apply,
  ROOT_RESOURCES and the others), signed by its provision-dev.py and
  sign-dev.sh. Two parts can be tuned:
  --min-ios version          the lowest iOS the package targets (17.0): the
                             asset symbols of the box's actool need 17
  --no-darwin-manifests      keep the manifests of direct dependencies that
                             test the build machine (canImport(Darwin),
                             os(Linux), os(macOS)) as they are; by default
                             tools/host-manifests.py answers them as on a
                             Mac, in a copy under <out>/xtool/.host-manifests
  Anything else: run the steps one by one and change the package between
  project and build, under <out>/xtool (regenerated by each project step).
  A project that needs it every time wraps the command in a script of its
  own: the options above, then its own changes between the steps.

Environment:
  ASC_KEY_ID, ASC_ISSUER_ID  the App Store Connect API key used to sign,
  ASC_KEY_PATH               read from xtool auth status when unset
  IOS_XCODEGEN_VERSION       the XcodeGen built for a project.yml (2.44.1)
  IOS_WIFI                   the same as --wifi
  IOS_UDID                   over Wi-Fi, the device when several are paired
  USER_NAME                  as root, the box's user whose tools are taken

Needs the ios environment, its SDK and the Apple sign-in with an App Store
Connect API key (devbox help ios), and a device paired through usbmuxd, or
over Wi-Fi through devbox ios pair (devbox help ios-wifi). As
root, it takes the tools, the SDK and the sign-in of the box's user. The
details: docs/dev-envs.md of dev-box, devbox help ios.
EOF
}

ios_xcode_py() {
  python3 "$IOS_XCODE_PY" "$@"
}

ios_xcode_product() { sed -n 's/^product: *//p' "$IOS_XCODE_PKG/xtool.yml"; }

# .package(...) of a --package name=path[@ref]: a git copy read at a commit
# (nothing written into it), a plain directory by path.
ios_xcode_local_dependency() {
  local spec="$1" path ref revision
  path="${spec%@*}"
  ref=""
  [ "$path" = "$spec" ] || ref="${spec##*@}"
  path="$(cd "$path" 2>/dev/null && pwd)" || ios_die "--package: no such directory: ${spec%@*}"
  if git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    revision="$(git -C "$path" rev-parse --verify -q "${ref:-HEAD}^{commit}" ||
      git -C "$path" rev-parse --verify -q "origin/$ref^{commit}")" ||
      ios_die "--package: no commit $ref in $path"
    echo ".package(url: \"file://$path\", revision: \"$revision\")"
  else
    echo ".package(path: \"$path\")"
  fi
}

# XcodeGen, built once from its sources. Then the .xcodeproj of the spec next
# to it, as on a Mac (the paths of the project, its Info.plist among them, are
# relative to it). What was not in that dir before (the .xcodeproj, a
# generated Info.plist, the .bsp of the generator) is removed at the end of
# the project step: IOS_XCODE_BEFORE lists what was there.
# Every file and dir under $1, the output dir left out (it may sit inside).
ios_xcode_entries() {
  find "$1" -path "$IOS_XCODE_OUT" -prune -o -print | sort
}

ios_xcode_xcodegen() {
  local spec="$1" dir xcodegen
  xcodegen="$IOS_XCODE_CACHE/xcodegen-$IOS_XCODEGEN_VERSION/.build/release/xcodegen"
  if [ ! -x "$xcodegen" ]; then
    log "XcodeGen $IOS_XCODEGEN_VERSION built from its sources (a minute, once)"
    rm -rf "$IOS_XCODE_CACHE/xcodegen-$IOS_XCODEGEN_VERSION"
    mkdir -p "$IOS_XCODE_CACHE"
    git clone -q --depth 1 --branch "$IOS_XCODEGEN_VERSION" -c advice.detachedHead=false \
      https://github.com/yonaskolb/XcodeGen "$IOS_XCODE_CACHE/xcodegen-$IOS_XCODEGEN_VERSION"
    (cd "$IOS_XCODE_CACHE/xcodegen-$IOS_XCODEGEN_VERSION" && swift build -c release --product xcodegen >/dev/null)
  fi
  dir="$(dirname "$spec")"
  IOS_XCODE_SPEC_DIR="$dir"
  IOS_XCODE_BEFORE="$(ios_xcode_entries "$dir")"
  log "$(basename "$spec"): Xcode project generated (XcodeGen)"
  # XcodeGen reads the user name, unset in a docker exec.
  USER="${USER:-$(id -un)}" "$xcodegen" generate --quiet --spec "$spec"
  # shellcheck disable=SC2012 # the newest .xcodeproj, the one just written
  IOS_XCODE_PROJECT="$(ls -td "$dir"/*.xcodeproj 2>/dev/null | head -n 1)"
  [ -n "$IOS_XCODE_PROJECT" ] || ios_die "XcodeGen wrote no .xcodeproj next to $spec"
}

# The framework of the Gradle project --kmp names, linked with its
# .xcframework by ios_kmp (kmp/build-framework.sh), the .xcframework copied
# inside the package and taken as a binary target.
ios_xcode_kmp() {
  local gradle="$IOS_XCODE_DIR" framework name
  while [ ! -x "$gradle/gradlew" ]; do
    [ "$gradle" != / ] || ios_die "--kmp: no gradlew in $IOS_XCODE_DIR or above"
    gradle="$(dirname "$gradle")"
  done
  ios_kmp "$gradle" --module "$IOS_XCODE_KMP" --dynamic --xcframework --out "$IOS_XCODE_OUT/kmp" ||
    ios_die "the framework did not link"
  framework="$(find "$IOS_XCODE_OUT/kmp" -maxdepth 1 -name '*.framework' -print -quit)"
  [ -n "$framework" ] || ios_die "--kmp: no framework in $IOS_XCODE_OUT/kmp"
  name="$(basename "$framework" .framework)"
  [ -d "$IOS_XCODE_OUT/kmp/$name.xcframework" ] || ios_die "--kmp: no $name.xcframework in $IOS_XCODE_OUT/kmp"
  mkdir -p "$IOS_XCODE_PKG/Frameworks"
  rm -rf "$IOS_XCODE_PKG/Frameworks/$name.xcframework"
  cp -R "$IOS_XCODE_OUT/kmp/$name.xcframework" "$IOS_XCODE_PKG/Frameworks/"
  ios_xcode_py binary-target "$IOS_XCODE_PKG/Package.swift" "$name" "Frameworks/$name.xcframework"
  log "$name.framework: a binary target of the package"
}

# After ship.sh: the Compose resources of --kmp, and its framework embedded
# when the build left it out.
ios_xcode_app_hook() {
  local app="$1" framework
  [ -n "$IOS_XCODE_KMP" ] || return 0
  framework="$(find "$IOS_XCODE_OUT/kmp" -maxdepth 1 -name '*.framework' -print -quit)"
  if [ ! -d "$app/Frameworks/$(basename "$framework")" ]; then
    mkdir -p "$app/Frameworks"
    cp -R "$framework" "$app/Frameworks/"
  fi
  if [ -d "$IOS_XCODE_OUT/kmp/compose-resources" ]; then
    rm -rf "$app/compose-resources"
    cp -R "$IOS_XCODE_OUT/kmp/compose-resources" "$app/compose-resources"
  fi
}

ios_xcode_project() {
  local pkg="$IOS_XCODE_PKG" spec name replacements=()
  IOS_XCODE_BEFORE=""
  case "$IOS_XCODE_PROJECT" in *.yml | *.yaml) ios_xcode_xcodegen "$IOS_XCODE_PROJECT" ;; esac
  log "xtool package from $(basename "$IOS_XCODE_PROJECT") ($IOS_XCODE_CONFIGURATION)"
  # .build stays: the packages fetched and built are kept from one run to the next.
  mkdir -p "$pkg"
  find "$pkg" -mindepth 1 -maxdepth 1 ! -name .build ! -name xtool -exec rm -rf {} +
  python3 "$OAD_DIR/tools/xcodeproj2xtool.py" "$IOS_XCODE_PROJECT" --out "$pkg" \
    --configuration "$IOS_XCODE_CONFIGURATION" ${IOS_XCODE_TARGET:+--target "$IOS_XCODE_TARGET"} 2>&1 |
    grep -v '^APP_ICON=' || true
  [ -f "$pkg/Package.swift" ] || ios_die "no package generated"

  for spec in "${IOS_XCODE_PACKAGES[@]}"; do
    name="${spec%%=*}"
    replacements+=("$name=$(ios_xcode_local_dependency "${spec#*=}")")
  done
  ios_xcode_py package "$pkg/Package.swift" "$IOS_XCODE_MIN_IOS" "${replacements[@]}"
  [ -z "$IOS_XCODE_KMP" ] || ios_xcode_kmp

  # Manifests that answer for Linux: copied, answered as on a Mac, by path
  # (tools/host-manifests.py, which resolves the package itself).
  if [ "$IOS_XCODE_DARWIN_MANIFESTS" = true ]; then
    local manifests
    log "packages fetched (swift package resolve), manifests that test the build machine looked for"
    manifests="$(cd "$pkg" && python3 "$OAD_DIR/tools/host-manifests.py" . 2>&1)" || {
      echo "$manifests" >&2
      ios_die "tools/host-manifests.py failed in $pkg"
    }
    grep -E 'answered as on a Mac|left as is' <<<"$manifests" | while IFS= read -r line; do log "$line"; done
  fi
  # What XcodeGen and the generator wrote next to the sources, gone now; the
  # deepest first, so a new dir is empty when its turn comes.
  if [ -n "$IOS_XCODE_BEFORE" ]; then
    comm -13 <(echo "$IOS_XCODE_BEFORE") <(ios_xcode_entries "$IOS_XCODE_SPEC_DIR") | sort -r |
      while IFS= read -r entry; do
        if [ -d "$entry" ]; then rmdir "$entry"; else rm -f "$entry"; fi
      done
  fi
  log "package: $pkg"
}

ios_xcode_build() {
  local product config=debug
  [ -f "$IOS_XCODE_PKG/Package.swift" ] || ios_xcode_project
  product="$(ios_xcode_product)"
  case "${IOS_XCODE_CONFIGURATION,,}" in *release*) config=release ;; esac
  log "$product ($config, ship.sh --device; the first build fetches and builds every package, minutes)"
  IOS_APP_HOOK=ios_xcode_app_hook ios_ship_build "$IOS_XCODE_PKG" "$config"
  log "app: $(ios_xcode_app) (unsigned)"
}

# The app the build step leaves, signed and installed by the install step.
ios_xcode_app() { echo "$IOS_XCODE_PKG/xtool/$(ios_xcode_product).app"; }

ios_xcode_install() {
  local app=""
  [ -f "$IOS_XCODE_PKG/xtool.yml" ] && app="$(ios_xcode_app)"
  if [ -z "$app" ] || [ ! -d "$app" ]; then
    ios_xcode_build
    app="$(ios_xcode_app)"
  fi
  ios_install "$app" "$IOS_XCODE_SIGNED_ID" "$IOS_XCODE_OUT/installed" "$IOS_XCODE_SIGNED_SUFFIX"
}

ios_xcode() {
  local dir="." step=run found=()
  IOS_XCODE_PROJECT="" IOS_XCODE_TARGET="" IOS_XCODE_CONFIGURATION=Debug IOS_XCODE_SIGNED_ID="" IOS_XCODE_OUT=""
  IOS_XCODE_KMP="" IOS_XCODE_SIGNED_SUFFIX="" IOS_XCODE_PACKAGES=()
  IOS_XCODE_MIN_IOS="17.0" IOS_XCODE_DARWIN_MANIFESTS=true
  while [ $# -gt 0 ]; do
    # shellcheck disable=SC2034 # IOS_WIFI: read by ios_connect of ios-common.sh
    case "$1" in
    --project) IOS_XCODE_PROJECT="${2:?--project needs a path}" && shift ;;
    --target) IOS_XCODE_TARGET="${2:?--target needs a name}" && shift ;;
    --configuration) IOS_XCODE_CONFIGURATION="${2:?--configuration needs a name}" && shift ;;
    --package)
      case "${2:-}" in *=*) IOS_XCODE_PACKAGES+=("$2") ;; *) ios_die "--package name=path[@ref]" ;; esac
      shift
      ;;
    --kmp) IOS_XCODE_KMP="${2:?--kmp needs a Gradle project, like :shared}" && shift ;;
    --signed-id) IOS_XCODE_SIGNED_ID="${2:?--signed-id needs an identifier}" && shift ;;
    --signed-suffix) IOS_XCODE_SIGNED_SUFFIX="${2:?--signed-suffix needs a suffix, like .kmp}" && shift ;;
    --out) IOS_XCODE_OUT="${2:?--out needs a dir}" && shift ;;
    --wifi) IOS_WIFI="${2:?--wifi needs the address of the device}" && shift ;;
    --min-ios) IOS_XCODE_MIN_IOS="${2:?--min-ios needs a version}" && shift ;;
    --no-darwin-manifests) IOS_XCODE_DARWIN_MANIFESTS=false ;;
    --no-asset-extensions)
      ios_die "--no-asset-extensions is gone: the shortcuts follow the project's ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS"
      ;;
    run | project | build | install | launch | logs) step="$1" ;;
    -*) ios_die "unknown option $1 (devbox ios xcode --help)" ;;
    *)
      [ -d "$1" ] || ios_die "no such project dir or step: $1"
      dir="$1"
      ;;
    esac
    shift
  done
  IOS_XCODE_DIR="$(cd "$dir" && pwd)"
  if [ -z "$IOS_XCODE_PROJECT" ]; then
    found=("$IOS_XCODE_DIR"/*.xcodeproj)
    [ -d "${found[0]}" ] || found=("$IOS_XCODE_DIR"/project.yml)
    [ -e "${found[0]}" ] || ios_die "no .xcodeproj nor project.yml in $IOS_XCODE_DIR (--project)"
    [ "${#found[@]}" -eq 1 ] || ios_die "several .xcodeproj in $IOS_XCODE_DIR: pick one with --project"
    IOS_XCODE_PROJECT="${found[0]}"
  fi
  [ -e "$IOS_XCODE_PROJECT" ] || ios_die "no such project: $IOS_XCODE_PROJECT"
  IOS_XCODE_PROJECT="$(cd "$(dirname "$IOS_XCODE_PROJECT")" && pwd)/$(basename "$IOS_XCODE_PROJECT")"
  IOS_XCODE_OUT="${IOS_XCODE_OUT:-$IOS_XCODE_DIR/build/devbox-ios}"
  mkdir -p "$IOS_XCODE_OUT"
  IOS_XCODE_OUT="$(cd "$IOS_XCODE_OUT" && pwd)"
  IOS_XCODE_PKG="$IOS_XCODE_OUT/xtool"
  [ -f "$OAD_DIR/tools/xcodeproj2xtool.py" ] || ios_die "omarchy-apple-dev has no xcodeproj2xtool.py: devbox dev-env ios"
  mise x swift -- swift sdk list 2>/dev/null | grep -qx darwin || ios_die "no iOS SDK: devbox ios sdk"
  case "$step" in
  project) ios_xcode_project ;;
  build)
    ios_xcode_project
    ios_xcode_build
    ;;
  install) ios_xcode_install ;;
  launch) ios_launch "$IOS_XCODE_OUT/installed" ;;
  logs) ios_logs "$IOS_XCODE_OUT/installed" ;;
  run)
    ios_xcode_project
    ios_xcode_build
    ios_xcode_install
    ios_launch "$IOS_XCODE_OUT/installed"
    ;;
  esac
}
