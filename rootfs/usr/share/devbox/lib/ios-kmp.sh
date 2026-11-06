# shellcheck shell=bash
# dev-box: the iOS framework of a Kotlin Multiplatform project, linked on
# Linux. Sourced by dev-box-ios for `devbox ios kmp`, not run.
#
# The link is kmp/build-framework.sh of omarchy-apple-dev: Gradle builds the
# klibs, and Kotlin/Native links them as if on a Mac, with the iOS runtime of
# its macOS distribution (from Maven Central, once, in
# ~/.cache/omarchy-apple-dev/kmp), the linker of the SDK's toolset and the iOS
# SDK the ios environment built (details: kmp/README.md of the clone).
# What is left here: the JDK of the box checked first, with the command that
# installs it, and the root case of the box (docker exec -u 0 from the
# host), where ios_root_env of ios-common.sh gives the tools and the SDK of
# the box's user; Gradle, Kotlin/Native and the cache stay in root's home.
# devbox ios xcode --kmp links the framework through here, then builds the
# app around it.

# shellcheck source=/usr/share/devbox/lib/ios-common.sh
. /usr/share/devbox/lib/ios-common.sh

ios_kmp_usage() {
  cat <<'USAGE'
Usage: devbox ios kmp [project dir] [--module :path] [--target ios_arm64|ios_simulator_arm64] [--out dir] [--dynamic] [--xcframework]

Links the iOS framework a Kotlin Multiplatform project declares
(binaries.framework), on Linux, from the klibs Gradle builds, with
kmp/build-framework.sh of omarchy-apple-dev. The project dir defaults to the
current one; --module picks one project of the build (every one that
declares a framework otherwise); --target defaults to ios_arm64, a device;
--out defaults to <module>/build/omarchy-kmp/<target>; --dynamic links a
dynamic framework even when the project declares a static one: swift build
in the box loads every member of a static archive (-all_load, from the
toolset), which the static framework of a Compose Multiplatform app does not
survive (Skia objects twice); --xcframework also wraps it as
<Name>.xcframework, for a SwiftPM binary target.
Needs the ios environment with its SDK (devbox ios sdk) and java (devbox
dev-env java). As root, it takes the tools of the box's user. The app around
the framework: devbox ios xcode --kmp (devbox ios xcode --help).
USAGE
}

ios_kmp() {
  local script="$OAD_DIR/kmp/build-framework.sh"
  [ -x "$script" ] || ios_die "omarchy-apple-dev has no kmp/build-framework.sh: devbox dev-env ios"
  if ! mise which java >/dev/null 2>&1; then
    err "Gradle needs a JDK: devbox dev-env java first"
    return 1
  fi
  "$script" "$@"
}
