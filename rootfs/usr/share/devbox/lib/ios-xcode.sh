# shellcheck shell=bash
# dev-box: an iOS app of an Xcode project (or an XcodeGen project.yml, or
# around the framework of a Kotlin Multiplatform build) built, signed,
# installed and launched on Linux. Sourced by dev-box-ios for
# `devbox ios xcode`, not run. Uses log and err of dev-box-ios.
#
# xcodeproj2xtool.py of omarchy-apple-dev turns the app target into an xtool
# package, and ios-common.sh builds it through ship.sh --device, signs,
# installs and launches it. What is left here, each part found on a real app
# (SwiftUI, Firebase, RxSwift, a private package, a Compose Multiplatform app):
#   - a project.yml generated into an .xcodeproj by XcodeGen, built once from
#     its sources into the cache; the files it writes next to the sources are
#     removed once the package is generated;
#   - the settings of one configuration (Debug by default), where the
#     generator only reads Release: identifier, name, version, Info.plist;
#   - manifests of direct dependencies that test the machine SwiftPM runs on
#     (canImport(Darwin), os(Linux), os(macOS)): RxSwift leaves RxCocoa out
#     on Linux. They are copied next to the build, the tests answered as on a
#     Mac, and declared by path in their place. A dependency of a dependency
#     cannot be: xtool builds the app from a package of its own;
#   - the SwiftUI and UIKit shortcuts of the asset symbols (Color.name,
#     UIColor(.name)), which Xcode writes and the actool of the box does not;
#     the symbols themselves need iOS 17, so the package targets it at least;
#   - with --kmp, the framework of a Kotlin Multiplatform build linked by
#     ios-kmp.sh, wrapped as an .xcframework the package takes as a binary
#     target (the generator drops OTHER_LDFLAGS and FRAMEWORK_SEARCH_PATHS),
#     and its Compose resources put into the .app.

# shellcheck source=/usr/share/devbox/lib/ios-kmp.sh
. /usr/share/devbox/lib/ios-kmp.sh

IOS_XCODE_PY="${IOS_XCODE_PY:-/usr/share/devbox/lib/ios-xcode.py}"
IOS_XCODE_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/devbox-ios-xcode"
IOS_XCODEGEN_VERSION="${IOS_XCODEGEN_VERSION:-2.44.1}"

ios_xcode_usage() {
  cat <<'EOF'
Usage: devbox ios xcode [project dir] [step] [options]

Builds the app of an Xcode project on Linux, then installs and launches it
on the iPhone or iPad plugged in. The project is the .xcodeproj of the dir,
or its project.yml (XcodeGen). Steps:
  run       build, install and launch (the default)
  project   the xtool package generated from the project
  build     the app and its .ipa, unsigned
  install   signed for the device plugged in, then installed
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
                             (devbox ios kmp), embedded with its Compose
                             resources. Needs java and, for a build with
                             Android targets, the Android SDK of sdk.dir
  --signed-id id             the identifier the app is signed under
                             (XTL-<team key>.<identifier>, like xtool, so it
                             never replaces the App Store or TestFlight one)
  --signed-suffix suffix     appended to that default identifier, for two
                             apps of one identifier on the device (.kmp)
  --out dir                  where it all goes (<dir>/build/devbox-ios)

Customizing:
  The package xcodeproj2xtool.py of omarchy-apple-dev generates is built by
  its ship.sh --device (app icon, resources at the root of the .app; its
  variables apply, ROOT_RESOURCES and the others), signed by its
  provision-dev.py and sign-dev.sh. What Xcode does and that chain does not
  is made up for on its own, each part with an option to tune or turn it off:
  --min-ios version          the lowest iOS the package targets (17.0): the
                             asset symbols of the box's actool need 17
  --no-darwin-manifests      keep the manifests of direct dependencies that
                             test the build machine (canImport(Darwin),
                             os(Linux), os(macOS)) as they are; by default
                             they are answered as on a Mac, in a copy under
                             <out>/deps
  --no-asset-extensions      no Color.name, UIColor.name, Image.name,
                             UIImage.name; by default they follow the
                             project's ASSETCATALOG_COMPILER_GENERATE_SWIFT_
                             ASSET_SYMBOL_EXTENSIONS (on unless NO)
  The app's Info.plist keys are also added to the one of its resource bundle
  (code built as a package reads Bundle.module).
  Anything else: run the steps one by one and change the package between
  project and build, under <out>/xtool (regenerated by each project step).
  A project that needs it every time wraps the command in a script of its
  own: the options above, then its own changes between the steps.

Environment:
  ASC_KEY_ID, ASC_ISSUER_ID  the App Store Connect API key used to sign,
  ASC_KEY_PATH               read from xtool auth status when unset
  IOS_XCODEGEN_VERSION       the XcodeGen built for a project.yml (2.44.1)
  USER_NAME                  as root, the box's user whose tools are taken

Needs the ios environment, its SDK and the Apple sign-in with an App Store
Connect API key (devbox help ios), and a device paired through usbmuxd. As
root, it takes the tools, the SDK and the sign-in of the box's user. The
details: docs/dev-envs.md of dev-box, devbox help ios.
EOF
}

ios_xcode_py() {
  OAD_TOOLS="$OAD_DIR/tools" python3 "$IOS_XCODE_PY" "$@"
}

ios_xcode_setting() {
  ios_xcode_py setting "$IOS_XCODE_PROJECT" "$IOS_XCODE_CONFIGURATION" "${IOS_XCODE_TARGET:--}" "$1"
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

# The framework of the Gradle project --kmp names, linked by ios_kmp, wrapped
# as an .xcframework inside the package and taken as a binary target.
ios_xcode_kmp() {
  local gradle="$IOS_XCODE_DIR" framework name
  while [ ! -x "$gradle/gradlew" ]; do
    [ "$gradle" != / ] || ios_die "--kmp: no gradlew in $IOS_XCODE_DIR or above"
    gradle="$(dirname "$gradle")"
  done
  ios_kmp "$gradle" --module "$IOS_XCODE_KMP" --dynamic --out "$IOS_XCODE_OUT/kmp" || ios_die "the framework did not link"
  framework="$(find "$IOS_XCODE_OUT/kmp" -maxdepth 1 -name '*.framework' -print -quit)"
  [ -n "$framework" ] || ios_die "--kmp: no framework in $IOS_XCODE_OUT/kmp"
  name="$(basename "$framework" .framework)"
  mkdir -p "$IOS_XCODE_PKG/Frameworks"
  ios_xcode_py xcframework "$framework" "$IOS_XCODE_PKG/Frameworks/$name.xcframework"
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
  local pkg="$IOS_XCODE_PKG" spec name kind replacements=() product
  IOS_XCODE_BEFORE=""
  case "$IOS_XCODE_PROJECT" in *.yml | *.yaml) ios_xcode_xcodegen "$IOS_XCODE_PROJECT" ;; esac
  log "xtool package from $(basename "$IOS_XCODE_PROJECT") ($IOS_XCODE_CONFIGURATION)"
  # .build stays: the packages fetched and built are kept from one run to the next.
  mkdir -p "$pkg"
  find "$pkg" -mindepth 1 -maxdepth 1 ! -name .build ! -name xtool -exec rm -rf {} +
  ios_xcode_py convert "$IOS_XCODE_PROJECT" "$pkg" "$IOS_XCODE_CONFIGURATION" \
    ${IOS_XCODE_TARGET:+--target "$IOS_XCODE_TARGET"} 2>&1 | grep -v '^APP_ICON=' || true
  [ -f "$pkg/Package.swift" ] || ios_die "no package generated"

  for spec in "${IOS_XCODE_PACKAGES[@]}"; do
    name="${spec%%=*}"
    replacements+=("$name=$(ios_xcode_local_dependency "${spec#*=}")")
  done
  ios_xcode_py package "$pkg/Package.swift" "$IOS_XCODE_MIN_IOS" "${replacements[@]}"
  [ -z "$IOS_XCODE_KMP" ] || ios_xcode_kmp

  # Manifests that answer for Linux: copied, answered as on a Mac, by path.
  if [ "$IOS_XCODE_DARWIN_MANIFESTS" = true ]; then
    log "packages fetched (swift package resolve)"
    (cd "$pkg" && swift package resolve >/dev/null) || ios_die "swift package resolve failed in $pkg"
    replacements=()
    while read -r name kind; do
      [ -n "$name" ] || continue
      if [ "$kind" != direct ]; then
        log "$name: its manifest tests the build machine, left as is (a dependency of a dependency)"
        continue
      fi
      log "$name: its manifest tests the build machine, answered as on a Mac"
      rm -rf "$IOS_XCODE_OUT/deps/$name"
      mkdir -p "$IOS_XCODE_OUT/deps"
      cp -R "$pkg/.build/checkouts/$name" "$IOS_XCODE_OUT/deps/$name"
      rm -rf "$IOS_XCODE_OUT/deps/$name/.git"
      ios_xcode_py patch-manifests "$IOS_XCODE_OUT/deps/$name"
      replacements+=("$name=.package(path: \"../deps/$name\")")
    done < <(ios_xcode_py darwin-manifests "$pkg/.build/checkouts" "$pkg/Package.swift")
    if [ "${#replacements[@]}" -gt 0 ]; then
      ios_xcode_py package "$pkg/Package.swift" "$IOS_XCODE_MIN_IOS" "${replacements[@]}"
      (cd "$pkg" && swift package resolve >/dev/null) || ios_die "swift package resolve failed in $pkg"
    fi
  fi

  product="$(ios_xcode_product)"
  local extensions
  extensions="$(ios_xcode_setting ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS)" ||
    ios_die "the settings of $(basename "$IOS_XCODE_PROJECT") could not be read"
  if [ "$IOS_XCODE_ASSET_EXTENSIONS" = true ] && [ "$extensions" != NO ]; then
    local catalogs=()
    while IFS= read -r name; do catalogs+=("$pkg/Sources/$product/$name"); done < <(ios_xcode_py catalogs "$pkg/Package.swift")
    [ "${#catalogs[@]}" -eq 0 ] ||
      ios_xcode_py symbols "$pkg/Sources/$product/DevboxAssetSymbolExtensions.swift" "${catalogs[@]}"
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
  IOS_APP_HOOK=ios_xcode_app_hook ios_ship_build "$IOS_XCODE_PKG" "$config" "$IOS_XCODE_OUT/$product.ipa"
  log "app: $IOS_XCODE_OUT/$product.ipa (unsigned)"
}

ios_xcode_install() {
  local ipa
  ipa="$(find "$IOS_XCODE_OUT" -maxdepth 1 -name '*.ipa' -print -quit)"
  if [ -z "$ipa" ]; then
    ios_xcode_build
    ipa="$(find "$IOS_XCODE_OUT" -maxdepth 1 -name '*.ipa' -print -quit)"
  fi
  ios_install "$ipa" "$IOS_XCODE_SIGNED_ID" "$IOS_XCODE_OUT/installed" "$IOS_XCODE_SIGNED_SUFFIX"
}

ios_xcode() {
  local dir="." step=run found=()
  IOS_XCODE_PROJECT="" IOS_XCODE_TARGET="" IOS_XCODE_CONFIGURATION=Debug IOS_XCODE_SIGNED_ID="" IOS_XCODE_OUT=""
  IOS_XCODE_KMP="" IOS_XCODE_SIGNED_SUFFIX="" IOS_XCODE_PACKAGES=()
  IOS_XCODE_MIN_IOS="17.0" IOS_XCODE_DARWIN_MANIFESTS=true IOS_XCODE_ASSET_EXTENSIONS=true
  while [ $# -gt 0 ]; do
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
    --min-ios) IOS_XCODE_MIN_IOS="${2:?--min-ios needs a version}" && shift ;;
    --no-darwin-manifests) IOS_XCODE_DARWIN_MANIFESTS=false ;;
    --no-asset-extensions) IOS_XCODE_ASSET_EXTENSIONS=false ;;
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
