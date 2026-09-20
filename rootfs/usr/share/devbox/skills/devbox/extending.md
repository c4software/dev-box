# Changing the box for good

The rule has one sentence. A lasting change is made in the dev-box repository
and takes effect with `just rebuild` on the host. Everything else is temporary,
and it is temporary in the worst way: it keeps working until the rebuild, then
it is gone with no error.

```
/usr/local/bin/      an edit here is lost on the next rebuild
/etc/devbox/         same
/usr/share/devbox/   same
```

The repository is public at <https://github.com/c4software/dev-box>. A clone in
`~/projets/dev-box` is the starting point for all of this:

```bash
git clone https://github.com/c4software/dev-box.git ~/projets/dev-box
```

The repository mirrors the image: `rootfs/usr/local/bin/devbox` in the clone
becomes `/usr/local/bin/devbox` in the box. Editing the file in the clone and
editing the file in the box look identical. Only one of them lasts.

## Where each kind of change goes

### A system package

`Dockerfile`, in the `pacman -Syu` list. Keep it alphabetically near its
neighbours and say in a comment what calls for it. Check the package exists on
Arch Linux ARM as well, since the box also builds for arm64 (Raspberry Pi 5)
from a different base image. A package that only exists on x86_64 breaks the Pi
build.

### A dev tool

Two cases.

- A tool every box should have: add it to
  `rootfs/etc/devbox/mise-config.toml`. That file is seeded into
  `~/.config/mise/config.toml`, so existing boxes pick it up through
  `devbox seed` when they have not edited theirs.
- A tool only you want: `mise use -g <tool>` in the box. Nothing to commit.

Check the name first: `mise registry | grep <tool>`, then
`mise ls-remote <tool> | tail -1`.

An interactive agent (`claude`, `pi`, `omp`, `codex`, `opencode`) also gets a
three-line wrapper in `rootfs/usr/local/bin/<name>`:

```bash
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g "<tool>" || exit 1
exec mise x "<tool>" -- "<cmd>" "$@"
```

The `mise use -g` makes the command work on the first call, before the
background install has finished, and after someone removed the tool from their
config.

### A new environment in `devbox dev-env`

Add a line to the `ENVS` array of `rootfs/usr/local/bin/dev-box-dev-env`
(`name|short description`) and an `install_<name>` function next to the others.
Only `mise use -g`: no pacman, no `curl | sh`. That is the whole point of the
command. PHP is the one exception, baked into the image through the `Dockerfile`
because mise would have to compile it; OCaml is not in it for the same reason.

### A new devbox command

A `rootfs/usr/local/bin/dev-box-<name>` script whose first lines carry the
headers `devbox` reads:

```bash
#!/usr/bin/env bash
# devbox:name=<name>
# devbox:summary=<one line, French, no final period>
# devbox:args=[a|b|c]
# devbox:hidden=true     # only if it is not a user-facing command
```

There is nothing to register anywhere. `devbox` finds it on the next start.
Keep the existing file names and their options untouched: the README, the
`justfile` and `entrypoint.sh` call them by name.

### A config file shipped to the home

Put the file under `rootfs/etc/devbox/` and add a
`<source>:<path relative to the home>` line to the `SEEDS` array of
`rootfs/usr/local/bin/dev-box-seed`. Then add it to the seed table in the
README. `dev-box-seed` takes care of the rest: laid down if missing, updated if
untouched, never overwritten if the user changed it.

### A guide in this skill

A new `.md` file in `rootfs/usr/share/devbox/skills/devbox/`, and a line for it
in the "Topic Guides" list of `SKILL.md`. Nothing else: the skill directory is
linked into the home, so the guide is there on the next start.

## Conventions

- bash, `set -euo pipefail`, no `eval`.
- shellcheck clean:
  `docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable -e SC1091,SC2088 <files>`
- Comments and script output in French. The README in English, plain prose, no
  arrows and no typographic dashes.
- The commands say what they are doing and what to run next. They install
  nothing the user did not ask for.
- Idempotent: running a command twice must not break anything.

## Testing without touching anything

Never test against the user's own `dev-box` container, and never write into
`data/`. Build, then start a throwaway container on a scratch directory:

```bash
docker compose build
scratch=$(mktemp -d)
docker run -d --name devbox-test \
  -e TS_DISABLE=true -e USER_NAME=dev -e UPDATE_CHECK_INTERVAL=0 \
  -v "$scratch/home:/home/dev" -v "$scratch/projets:/home/dev/projets" \
  --device /dev/net/tun --cap-add NET_ADMIN --cap-add NET_RAW \
  dev-box-dev-box

docker logs -f devbox-test          # wait for "mise : outils installés"
docker exec -u dev devbox-test zsh -lc 'devbox --help'
docker rm -f devbox-test && rm -rf "$scratch"
```

A single file can be copied into a running test container with `docker cp` to
iterate faster, but the real check is always a fresh build.

## Then

Commit, push, and on the host:

```bash
just rebuild    # fresh base image, packages refreshed, container restarted
```

`just up` is enough when only `rootfs/` changed and the Arch packages can stay
where they are.
