# shellcheck shell=bash
# dev-box: what the image was built from, and how to reach the repository it
# came from. Sourced by dev-box-check-updates, dev-box-changelog and
# dev-box-status, not run.
#
# /etc/devbox/release is written at build time by the Dockerfile:
#   DEVBOX_COMMIT   the commit of the dev-box repo the image was built from
#   DEVBOX_REPO     that repo, as the clone knew it (ssh or https)
#   DEVBOX_BRANCH   the branch a local build follows
#   DEVBOX_VERSION  the release tag (v1.5), or git describe for a local build
#   DEVBOX_SOURCE   release for the image published by the workflow, local
#                   for a build made on the host
#   DEVBOX_IMAGE_NAME  the published image, ghcr.io/c4software/dev-box
#   DEVBOX_TAG_SUFFIX  the suffix of its tags: -arm64 for the arm64 image
#                   (latest-arm64, v1.12-arm64), empty for the amd64 one
# Images built before DEVBOX_VERSION and DEVBOX_SOURCE existed carry neither:
# local. The published images from before the split into one image per
# architecture (a single multi-arch latest) carry no DEVBOX_IMAGE_NAME nor
# DEVBOX_TAG_SUFFIX. DEVBOX_VERSION is always the git tag (v1.12), never the
# image tag: it is what the box compares with the v* tags of the repo.
#
# Everything that touches the network goes through git, bounded by a timeout,
# with GITHUB_TOKEN as the authentication when it is set (a private repo).

DEVBOX_COMMIT="unknown"; DEVBOX_REPO=""; DEVBOX_BRANCH="main"
DEVBOX_VERSION=""; DEVBOX_SOURCE=""; DEVBOX_IMAGE_NAME=""; DEVBOX_TAG_SUFFIX=""
# shellcheck source=/dev/null
[ -r /etc/devbox/release ] && . /etc/devbox/release
[ -n "$DEVBOX_BRANCH" ] || DEVBOX_BRANCH="main"
[ -n "$DEVBOX_SOURCE" ] || DEVBOX_SOURCE="local"
# A version given as the image tag (v1.12-arm64) is still the release v1.12.
case "$DEVBOX_VERSION" in
  *-arm64) DEVBOX_VERSION="${DEVBOX_VERSION%-arm64}"; DEVBOX_TAG_SUFFIX="-arm64" ;;
esac

# The repo as an https URL: the box has no ssh key for it. host:path becomes
# host/path before the scheme goes in front, so that the colon replaced is the
# one after the host, not the one of https:.
devbox_repo_url() {
  local url="$DEVBOX_REPO"
  case "$url" in
    git@*:*)     url="${url#git@}"; url="https://${url/:/\/}" ;;
    ssh://git@*) url="https://${url#ssh://git@}" ;;
  esac
  printf '%s' "$url"
}

# What the box calls itself: the release tag, or the short commit.
devbox_version() {
  printf '%s' "${DEVBOX_VERSION:-${DEVBOX_COMMIT:0:7}}"
}

# The architecture of the machine, as the image tags name it: arm64 or amd64
# (anything else as the kernel says it). Read from the kernel rather than
# uname: an amd64 image emulated on an arm64 host (Docker Desktop on Apple
# silicon, qemu on a Pi) says x86_64 to uname, the kernel still says aarch64.
devbox_machine_arch() {
  local arch=""
  [ -r /proc/sys/kernel/arch ] && IFS= read -r arch < /proc/sys/kernel/arch
  [ -n "$arch" ] || arch="$(uname -m)"
  case "$arch" in
    aarch64|arm64) printf 'arm64' ;;
    x86_64|amd64) printf 'amd64' ;;
    *) printf '%s' "$arch" ;;
  esac
}

# The published image to pull, name:latest plus the suffix given (none by
# default: the one this image was published under).
devbox_image_ref() {
  local name="$DEVBOX_IMAGE_NAME" suffix="${1-$DEVBOX_TAG_SUFFIX}" repo
  if [ -z "$name" ]; then
    name="ghcr.io/c4software/dev-box"
    if repo="$(devbox_github_repo 2>/dev/null)"; then
      name="ghcr.io/$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')"
    fi
  fi
  printf '%s:latest%s' "$name" "$suffix"
}

# The published image this machine should pull: the arm64 one on arm64, the
# amd64 one on amd64, whatever image the box runs now.
devbox_pull_ref() {
  case "$(devbox_machine_arch)" in
    arm64) devbox_image_ref -arm64 ;;
    amd64) devbox_image_ref "" ;;
    *) devbox_image_ref ;;
  esac
}

# One line when the published image this box runs is not the one of its
# machine: an arm64 machine on the amd64 image (latest, emulated and slow), or
# on the multi-arch latest published before the images were split per
# architecture, whose next pull would bring the amd64 image. Nothing, and
# status 1, otherwise. A local build always matches: it is built on the
# machine.
devbox_image_arch_advice() {
  local now
  [ "$DEVBOX_SOURCE" = "release" ] || return 1
  [ "$(devbox_machine_arch)" = "arm64" ] || return 1
  [ "$DEVBOX_TAG_SUFFIX" != "-arm64" ] || return 1
  if [ -n "$DEVBOX_IMAGE_NAME" ]; then
    now="this arm64 machine runs the amd64 image $(devbox_image_ref ""), emulated"
  else
    now="$(devbox_image_ref "") is amd64 only now, arm64 has its own image"
  fi
  printf '%s: set DEVBOX_IMAGE=%s in .env on the host, then docker compose pull && docker compose up -d\n' \
    "$now" "$(devbox_image_ref -arm64)"
}

devbox_git() {
  local auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(-c "http.extraheader=Authorization: Bearer $GITHUB_TOKEN")
  fi
  GIT_TERMINAL_PROMPT=0 timeout 30 git "${auth[@]}" "$@"
}

# The newest release published as an arm64 image, v1.12 for the tag
# v1.12-arm64 of the registry. The arm64 image is built by hand, after the
# release (build-arm64.yml): the newest v* tag of the repo may have none yet,
# and an arm64 box that was told to pull it would get the same image again.
# ghcr.io lists the tags of a public image with an anonymous token, two small
# requests. Only for an image on ghcr.io; status 1 when it cannot be read.
devbox_latest_arm64_release() {
  local repo token
  case "$DEVBOX_IMAGE_NAME" in
    ghcr.io/*/*) repo="${DEVBOX_IMAGE_NAME#ghcr.io/}" ;;
    *) return 1 ;;
  esac
  command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 1
  token="$(curl -fsSL --max-time 15 "https://ghcr.io/token?scope=repository:$repo:pull" 2>/dev/null \
    | jq -r '.token // empty' 2>/dev/null)" || return 1
  [ -n "$token" ] || return 1
  curl -fsSL --max-time 15 -H "Authorization: Bearer $token" \
      "https://ghcr.io/v2/$repo/tags/list?n=1000" 2>/dev/null \
    | jq -r '.tags[]?' 2>/dev/null \
    | sed -n 's/^\(v[0-9][0-9.]*\)-arm64$/\1/p' | sort -V | tail -n 1 | grep .
}

# The newest release tag of the repo and the commit it points to, "tag
# commit". A release is v followed by numbers and dots (v1.5, v2.0.1): sort -V
# puts v1.5-rc1 after v1.5, so a pre-release would pass for the latest.
# An annotated tag is listed twice by ls-remote: the ^{} line is the commit.
# For the arm64 image, the newest release that has an arm64 image, with no
# commit ("tag "); the newest v* tag when the registry cannot be read.
devbox_latest_release() {
  local url refs tag commit
  if [ "$DEVBOX_TAG_SUFFIX" = "-arm64" ] && tag="$(devbox_latest_arm64_release)"; then
    printf '%s \n' "$tag"
    return 0
  fi
  url="$(devbox_repo_url)"
  [ -n "$url" ] || return 1
  refs="$(devbox_git ls-remote --tags "$url" 2>/dev/null)" || return 1
  tag="$(printf '%s\n' "$refs" | awk '{ print $2 }' \
    | sed -n 's#^refs/tags/\(v[0-9][0-9.]*\)$#\1#p' | sort -V | tail -n 1)"
  [ -n "$tag" ] || return 1
  commit="$(printf '%s\n' "$refs" | awk -v r="refs/tags/$tag^{}" '$2 == r { print $1 }')"
  [ -n "$commit" ] \
    || commit="$(printf '%s\n' "$refs" | awk -v r="refs/tags/$tag" '$2 == r { print $1 }')"
  printf '%s %s\n' "$tag" "$commit"
}

# The commit at the head of the branch a local build follows.
devbox_branch_head() {
  local url head
  url="$(devbox_repo_url)"
  [ -n "$url" ] || return 1
  head="$(devbox_git ls-remote "$url" "refs/heads/$DEVBOX_BRANCH" 2>/dev/null \
    | awk 'NR == 1 { print $1 }')" || return 1
  [ -n "$head" ] || return 1
  printf '%s\n' "$head"
}

# True when version $1 comes after $2 (sort -V). An unknown $2 is older.
devbox_version_newer() {
  [ -n "$2" ] || return 0
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

# Prints one file of the repo at a ref (refs/tags/v1.5, refs/heads/main).
# A shallow fetch with no blobs, then the one blob asked for: a few hundred
# KB whatever the size of the repo, nothing left behind.
devbox_repo_file() {
  local ref="$1" path="$2" url dir rc=0
  url="$(devbox_repo_url)"
  [ -n "$url" ] || return 1
  dir="$(mktemp -d)"
  if git -C "$dir" init -q 2>/dev/null \
    && git -C "$dir" remote add origin "$url" \
    && devbox_git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$ref" 2>/dev/null; then
    devbox_git -C "$dir" show "FETCH_HEAD:$path" 2>/dev/null || rc=1
  else
    rc=1
  fi
  rm -rf "$dir"
  return "$rc"
}

# Where the next image comes from: the latest release for the published
# image, the head of the branch for a local build. Prints "ref label".
devbox_upcoming_ref() {
  local latest
  if [ "$DEVBOX_SOURCE" = "release" ]; then
    latest="$(devbox_latest_release)" || return 1
    printf 'refs/tags/%s %s\n' "${latest%% *}" "${latest%% *}"
  else
    printf 'refs/heads/%s %s\n' "$DEVBOX_BRANCH" "$DEVBOX_BRANCH"
  fi
}

# --- Release notes -----------------------------------------------------------
#
# The changelog of the box is the list of GitHub releases of the repo: the
# workflow creates one per v* tag, its notes taken from the annotation of the
# tag. They are kept in a cache, so that the login reads a file and never the
# network; devbox check and devbox changelog refresh it.

DEVBOX_RELEASES_CACHE="$HOME/.cache/dev-box/releases.md"

# owner/repo when the repo is on github.com, where the releases are read.
devbox_github_repo() {
  local url
  url="$(devbox_repo_url)"
  case "$url" in
    https://github.com/*/*)
      url="${url#https://github.com/}"; url="${url%/}"; url="${url%.git}"
      printf '%s' "$url"
      ;;
    *) return 1 ;;
  esac
}

# The release notes, newest first, in the format of the cache:
#   ## v1.7 2026-09-24
#   the notes, as written in the annotation of the tag
# Only v<numbers> releases, no draft and no pre-release: the tags the box
# compares itself with. A heading inside the notes loses its #, so that it
# cannot pass for a release.
devbox_fetch_releases() {
  local repo auth=()
  repo="$(devbox_github_repo)" || return 1
  command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 1
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  curl -fsSL --max-time 20 "${auth[@]}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$repo/releases?per_page=100" | jq -r '
      [ .[] | select((.draft | not) and (.prerelease | not))
        | select(.tag_name | test("^v[0-9][0-9.]*$")) ]
      | sort_by(.tag_name | ltrimstr("v") | split(".") | map(select(. != "") | tonumber))
      | reverse[]
      | "## \(.tag_name) \((.published_at // .created_at // "")[0:10])",
        ((.body // "") | gsub("\r"; "") | split("\n") | map(sub("^#+ *"; "")) | .[]),
        ""'
}

# Refreshes the cache. On failure the previous cache stays as it was.
devbox_refresh_releases() {
  local tmp
  mkdir -p "${DEVBOX_RELEASES_CACHE%/*}"
  tmp="$(mktemp "$DEVBOX_RELEASES_CACHE.XXXXXX")"
  if devbox_fetch_releases > "$tmp"; then
    mv "$tmp" "$DEVBOX_RELEASES_CACHE"
  else
    rm -f "$tmp"
    return 1
  fi
}
