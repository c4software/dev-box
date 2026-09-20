#!/usr/bin/env bash
# Backs the box up: the filtered home and the projects directory, into a
# tar.zst archive written into <dest_dir> (./backups by default, git-ignored).
#
# Usage: scripts/backup.sh [--with-tailscale] [dest_dir]
#
# What goes in: data/home (minus the caches that rebuild themselves), the
# projects directory (PROJECTS_DIR, whole git repos, .git/objects included),
# and a copy of .env and compose.override.yaml when they exist.
# What stays out by default: data/tailscale (the node identity, we do not want
# to duplicate it without being asked). See --with-tailscale.
set -euo pipefail

# We always work from the root of the repo: the paths stored in the archive
# are relative to it, which makes restoring trivial.
cd "$(dirname "$0")/.."
repo_root="$PWD"

with_tailscale=0
dest_dir=""

for arg in "$@"; do
    case "$arg" in
        --with-tailscale) with_tailscale=1 ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
        *) dest_dir="$arg" ;;
    esac
done

dest_dir="${dest_dir:-./backups}"

# Values from .env (TS_HOSTNAME to name the archive, PROJECTS_DIR to know what
# to back up). set -a exports everything the file defines.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091  # .env is written by the user
    . ./.env
    set +a
fi
ts_hostname="${TS_HOSTNAME:-dev-box}"
projects_dir="${PROJECTS_DIR:-./data/projets}"

# tar hands the compression to the zstd binary, which is not always installed
# (a minimal Debian image on a Raspberry Pi, for instance).
if ! command -v zstd >/dev/null 2>&1; then
    echo "zstd not found: install it (pacman -S zstd, or apt install zstd)." >&2
    exit 1
fi

if [ ! -d data/home ]; then
    echo "data/home not found: nothing to back up (wrong directory?)" >&2
    exit 1
fi

mkdir -p "$dest_dir"
dest_dir="$(cd "$dest_dir" && pwd)"
archive="$dest_dir/dev-box-${ts_hostname}-$(date +%Y%m%d-%H%M%S).tar.zst"

# Members of the archive, as paths relative to the root of the repo.
members=(data/home)

# The projects directory normally lives in the repo (./data/projets). When it
# points elsewhere (another disk), it goes under projets-external/ in the
# archive: restoring must not overwrite it in the wrong place.
transform=()
projects_abs="$(cd "$projects_dir" 2>/dev/null && pwd || true)"
if [ -z "$projects_abs" ]; then
    echo "Warning: $projects_dir not found, the projects are not backed up." >&2
elif [ "${projects_abs#"$repo_root"/}" != "$projects_abs" ]; then
    members+=("${projects_abs#"$repo_root"/}")
else
    members+=("$projects_abs")
    transform+=(--transform "s,^${projects_abs#/},projets-external,")
    echo "Note: PROJECTS_DIR is outside the repo ($projects_abs)."
    echo "      It goes into the archive under projets-external/ and has to be moved back by hand."
fi

if [ -f .env ]; then members+=(.env); fi
if [ -f compose.override.yaml ]; then members+=(compose.override.yaml); fi
if [ "$with_tailscale" -eq 1 ] && [ -d data/tailscale ]; then
    members+=(data/tailscale)
fi

# Caches and artefacts that rebuild themselves: useless, bulky, and rebuilt on
# the first start or the first `mise install`.
excludes=(
    --exclude=data/home/.cache
    --exclude=data/home/.local/share/mise
    --exclude=data/home/.local/share/nvim
    --exclude=data/home/.local/state/nvim
    --exclude=data/home/.local/share/dotarchy
    --exclude=data/home/.local/share/containers
    --exclude=data/home/.local/share/lazyvim-starter
    --exclude=data/home/.npm
    --exclude=data/home/.bun
    --exclude='*/node_modules'
)

# data/home can hold root-owned files (and data/tailscale is root:root), so we
# only go through sudo when something is not readable as is.
# The test skips what tar would exclude anyway (the mise caches hold broken
# links) and symbolic links (tar archives them without following them). The
# ~/projets directory, a mount point created by Docker, is a root-owned
# directory but a readable one: it is not a problem.
prune=()
for e in "${excludes[@]}"; do
    pat="${e#--exclude=}"
    case "$pat" in
        \*/*) prune+=(-name "${pat#*/}" -prune -o) ;;
        *)    prune+=(-path "$pat" -prune -o) ;;
    esac
done
sudo_cmd=()
unreadable=""
for m in "${members[@]}"; do
    [ -e "$m" ] || continue
    if ! find "$m" "${prune[@]}" -print >/dev/null 2>&1 \
       || [ -n "$(find "$m" "${prune[@]}" ! -type l ! -readable -print -quit 2>/dev/null)" ]; then
        unreadable="$m"
        break
    fi
done
if [ -n "$unreadable" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        : # already root
    elif command -v sudo >/dev/null 2>&1; then
        echo "Unreadable files in $unreadable: going through sudo."
        sudo_cmd=(sudo)
    else
        echo "Unreadable files in $unreadable, and sudo is missing." >&2
        exit 1
    fi
fi

echo "Archive: $archive"
# --numeric-owner: the UID/GID are kept (1000:1000 on the box side, root for
# tailscale) without depending on the user names of the restoring machine.
"${sudo_cmd[@]}" tar --zstd --numeric-owner \
    "${excludes[@]}" \
    "${transform[@]}" \
    -cf "$archive" \
    "${members[@]}"

# An archive created under sudo would belong to root: we hand it back to the user.
if [ "${#sudo_cmd[@]}" -gt 0 ]; then
    sudo chown "$(id -u):$(id -g)" "$archive"
fi

# Check: the archive is read back end to end (decompression included).
count="$(tar -tf "$archive" | wc -l)"
size="$(du -h "$archive" | cut -f1)"
echo "OK: $count entries, $size"
