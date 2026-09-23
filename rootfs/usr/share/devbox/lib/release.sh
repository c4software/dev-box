# shellcheck shell=bash
# dev-box: what the image was built from, and how to reach the repository it
# came from. Sourced by dev-box-check-updates and dev-box-changelog, not run.
#
# /etc/devbox/release is written at build time by the Dockerfile:
#   DEVBOX_COMMIT   the commit of the dev-box repo the image was built from
#   DEVBOX_REPO     that repo, as the clone knew it (ssh or https)
#   DEVBOX_BRANCH   the branch a local build follows
#   DEVBOX_VERSION  the release tag (v1.5), or git describe for a local build
#   DEVBOX_SOURCE   release for the image published by the workflow, local
#                   for a build made on the host
# Images built before these two fields existed carry neither: local.
#
# Everything that touches the network goes through git, bounded by a timeout,
# with GITHUB_TOKEN as the authentication when it is set (a private repo).

DEVBOX_COMMIT="unknown"; DEVBOX_REPO=""; DEVBOX_BRANCH="main"
DEVBOX_VERSION=""; DEVBOX_SOURCE=""
# shellcheck source=/dev/null
[ -r /etc/devbox/release ] && . /etc/devbox/release
[ -n "$DEVBOX_BRANCH" ] || DEVBOX_BRANCH="main"
[ -n "$DEVBOX_SOURCE" ] || DEVBOX_SOURCE="local"

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

devbox_git() {
  local auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(-c "http.extraheader=Authorization: Bearer $GITHUB_TOKEN")
  fi
  GIT_TERMINAL_PROMPT=0 timeout 30 git "${auth[@]}" "$@"
}

# The newest v* tag of the repo and the commit it points to, "tag commit".
# An annotated tag is listed twice by ls-remote: the ^{} line is the commit.
devbox_latest_release() {
  local url refs tag commit
  url="$(devbox_repo_url)"
  [ -n "$url" ] || return 1
  refs="$(devbox_git ls-remote --tags "$url" 2>/dev/null)" || return 1
  tag="$(printf '%s\n' "$refs" | awk '{ print $2 }' \
    | sed -n 's#^refs/tags/\(v[^^]*\)$#\1#p' | sort -V | tail -n 1)"
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
