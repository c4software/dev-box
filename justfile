# Host-side commands to drive the box (just >= 1.30).
# The variables of .env are loaded and exported into the environment of the
# recipes: read them with ${VAR:-default} straight from the shell.
set dotenv-load

# Container name (container_name in compose.yaml).
container := "dev-box"

# Repo commit, baked into the image at build time (see compose.yaml): the
# update check inside the box then knows when the image lags the repo.
export DEVBOX_COMMIT := `git rev-parse HEAD 2>/dev/null || echo unknown`
export DEVBOX_REPO := `git remote get-url origin 2>/dev/null || true`
export DEVBOX_BRANCH := `git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main`
export DEVBOX_VERSION := `git describe --tags --always 2>/dev/null || true`

# List the available commands.
default:
    @just --list

# With DEVBOX_IMAGE set in .env the image comes from the registry instead of a
# local build: up and rebuild pull it, the Dockerfile is never run here.

# Build the image if needed (or pull it with DEVBOX_IMAGE) and start the box.
up:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "${DEVBOX_IMAGE:-}" ]; then
        docker compose pull
        docker compose up -d
    else
        docker compose up -d --build
    fi

# --pull fetches a newer archlinux:latest, --no-cache forces the `pacman -Syu`
# to run again: without it the pacman layer stays cached as long as the base
# image keeps the same digest, and the packages would stay frozen at the date
# of the first build.

# Update Arch (base image and packages) and restart the box.
rebuild:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "${DEVBOX_IMAGE:-}" ]; then
        docker compose pull
    else
        docker compose build --pull --no-cache
    fi
    docker compose up -d

# Pull the published image (DEVBOX_IMAGE in .env) and restart on it.
pull:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${DEVBOX_IMAGE:-}" ]; then
        echo "DEVBOX_IMAGE is not set in .env: nothing to pull, just up builds the image locally" >&2
        exit 1
    fi
    docker compose pull
    docker compose up -d

# Stop and remove the container (the ./data/ volumes are kept).
down:
    docker compose down

# Restart the container without rebuilding.
restart:
    docker compose restart

# Follow the entrypoint logs (dotarchy-sync, tailscale up, ...).
logs:
    docker compose logs -f --tail=100

# State of the container, the healthcheck, and the image against the repo.
status:
    #!/usr/bin/env bash
    set -euo pipefail
    docker compose ps
    docker inspect -f 'health: {{{{ .State.Health.Status }} ({{{{ len .State.Health.Log }} check(s))' {{ container }} 2>/dev/null \
      || echo "health: n/a (container stopped, or no healthcheck)"
    # What the image records (/etc/devbox/release) against the repo. The
    # published image (DEVBOX_IMAGE) is compared with the newest release tag
    # of origin, the next one `just pull` can fetch; a local build with the
    # local checkout. Also the comparison the box cannot make alone when the
    # repo is private.
    release="$(docker run --rm --entrypoint sh "${DEVBOX_IMAGE:-dev-box-dev-box}" -c 'cat /etc/devbox/release' 2>/dev/null || true)"
    built="$(printf '%s\n' "$release" | sed -n 's/^DEVBOX_COMMIT=//p')"
    version="$(printf '%s\n' "$release" | sed -n 's/^DEVBOX_VERSION=//p')"
    [ -n "$built" ] || built=unknown
    [ -n "$version" ] || version="${built:0:7}"
    if [ "$built" = unknown ]; then
        echo "image: unknown commit (built from a context without .git), just rebuild to bake it in"
    elif [ -n "${DEVBOX_IMAGE:-}" ]; then
        # v followed by numbers and dots: a pre-release is not a release
        refs="$(GIT_TERMINAL_PROMPT=0 timeout 30 git ls-remote --tags origin 2>/dev/null || true)"
        tag="$(printf '%s\n' "$refs" | awk '{ print $2 }' \
          | sed -n 's#^refs/tags/\(v[0-9][0-9.]*\)$#\1#p' | sort -V | tail -n 1)"
        commit="$(printf '%s\n' "$refs" | awk -v r="refs/tags/$tag^{}" '$2 == r { print $1 }')"
        [ -n "$commit" ] || commit="$(printf '%s\n' "$refs" | awk -v r="refs/tags/$tag" '$2 == r { print $1 }')"
        if [ -z "$tag" ]; then
            echo "image: $version, could not read the release tags of origin"
        elif [ "$commit" = "$built" ]; then
            echo "image: $version, the latest release"
        else
            echo "image: $version, $tag released, run just pull (the workflow publishes it a few minutes after the tag)"
        fi
    else
        head="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
        if [ "$built" = "$head" ]; then
            echo "image: up to date with the checkout ($version)"
        else
            echo "image: built on ${built:0:7}, checkout at ${head:0:7}, run just rebuild"
        fi
    fi

# Open a zsh login shell inside the box, as your user.
shell:
    docker exec -it -u "${USER_NAME:-dev}" {{ container }} zsh -l

# Connect over SSH: Tailscale, or the published port if TS_DISABLE=true.
ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${TS_DISABLE:-false}" = "true" ]; then
        ssh -p "${SSH_PORT:-2222}" "${USER_NAME:-dev}@${SSH_BIND:-127.0.0.1}"
    else
        ssh "${USER_NAME:-dev}@${TS_HOSTNAME:-dev-box}"
    fi

# Update the box: dev-box-update takes dotfiles|tools|seed|all, all by default.
update what="":
    docker exec -it -u "${USER_NAME:-dev}" {{ container }} zsh -lc "dev-box-update {{ what }}"

# Back up the filtered home and the projects into a tar.zst archive.
backup dest="":
    ./scripts/backup.sh "{{ dest }}"

# Restore an archive written by `just backup`.
restore archive:
    ./scripts/restore.sh "{{ archive }}"
