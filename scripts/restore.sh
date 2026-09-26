#!/usr/bin/env bash
# Restores an archive written by scripts/backup.sh, at the root of the repo.
#
# Usage: scripts/restore.sh <archive.tar.zst> [--yes]
#
# The container is stopped before the extraction, then the archive is unpacked
# over what is there: nothing is deleted, only the files the archive holds are
# overwritten. --yes skips the prompt (and is required outside a terminal).
set -euo pipefail

cd "$(dirname "$0")/.."

archive=""
assume_yes=0

for arg in "$@"; do
    case "$arg" in
        --yes|-y) assume_yes=1 ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
        *) archive="$arg" ;;
    esac
done

# Same dependency as the backup: tar calls the zstd binary.
if ! command -v zstd >/dev/null 2>&1; then
    echo "zstd not found: install it (pacman -S zstd, or apt install zstd)." >&2
    exit 1
fi

if [ -z "$archive" ]; then
    echo "Usage: scripts/restore.sh <archive.tar.zst> [--yes]" >&2
    exit 1
fi
if [ ! -f "$archive" ]; then
    echo "Archive not found: $archive" >&2
    exit 1
fi
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"

# The contents of the archive: used to list what already exists and will be
# overwritten, and to know whether sudo is needed (entries owned by another UID).
mapfile -t entries < <(tar -tf "$archive")
if [ "${#entries[@]}" -eq 0 ]; then
    echo "Empty archive: $archive" >&2
    exit 1
fi

echo "Archive: $archive (${#entries[@]} entries)"
echo "Restored roots:"
printf '%s\n' "${entries[@]}" | awk -F/ '{print $1}' | sort -u | sed 's/^/  - /'

existing=()
for top in $(printf '%s\n' "${entries[@]}" | awk -F/ '{print $1}' | sort -u); do
    if [ -e "$top" ]; then existing+=("$top"); fi
done
if [ "${#existing[@]}" -gt 0 ]; then
    echo "Already there, overwritten file by file (nothing is deleted):"
    printf '  ! %s\n' "${existing[@]}"
else
    echo "Nothing that exists will be overwritten."
fi

if printf '%s\n' "${entries[@]}" | grep -q '^projets-external/'; then
    echo "Note: the archive holds projets-external/ (PROJECTS_DIR outside the repo)."
    echo "      It is extracted here, and has to be moved back by hand."
fi

# Confirmation: a plain refusal when there is no terminal.
if [ "$assume_yes" -eq 0 ]; then
    if [ ! -t 0 ]; then
        echo "Non-interactive: run it again with --yes to confirm." >&2
        exit 1
    fi
    read -r -p "Restore into $PWD? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 1 ;;
    esac
fi

# The container has to be stopped: it writes into the mounted home all the time.
if command -v docker >/dev/null 2>&1; then
    echo "Stopping the container..."
    docker compose stop || echo "docker compose stop failed (container already stopped?)"
else
    echo "docker is missing: the container was not stopped."
fi

# Restoring files owned by another UID (root for data/tailscale) needs the
# rights; otherwise we extract as is, under the current user.
sudo_cmd=()
if [ "$(id -u)" -ne 0 ] && tar --numeric-owner -tvf "$archive" \
        | awk -v me="$(id -u)" '{split($2, o, "/"); if (o[1] != me) found=1} END {exit !found}'; then
    if command -v sudo >/dev/null 2>&1; then
        echo "The archive holds files from another user: going through sudo."
        sudo_cmd=(sudo)
    else
        echo "Warning: sudo is missing, the owners will not be restored." >&2
    fi
fi

"${sudo_cmd[@]}" tar --zstd --numeric-owner -xpf "$archive" -C "$PWD"

echo "Restore done."
echo "Start the box again: docker compose up -d"
