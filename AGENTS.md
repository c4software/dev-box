# Contributing to dev-box

This file is for humans and coding agents alike. The long version, with the
recipe for each kind of change, lives in
`rootfs/usr/share/devbox/skills/devbox/extending.md`. Read it before touching
anything beyond a typo.

## How the repository maps to the box

`rootfs/` mirrors the image: `rootfs/usr/local/bin/devbox` in the repo becomes
`/usr/local/bin/devbox` in the container. The `Dockerfile` builds the image,
`compose.yaml` runs it, the `justfile` wraps the host commands. The user's home
lives in `./data/home` and survives every rebuild. That last point is the whole
reason for the rule below.

## The rule: a structural change ships with a migration

The image is rebuilt, the home is not. Anything that changes what an existing
home is expected to look like must come with a migration in
`rootfs/usr/share/devbox/migrations/`, or existing boxes silently stay on the
old layout. This applies whenever you:

- move, rename or remove a file or directory the box writes into the home
  (`~/.config/dev-box/`, `~/.config/mise/`, `~/.claude/`, `~/.pi/`, `~/.omp/`);
- change the format or the meaning of a state file (`agent`, `packages`,
  `migrations`, the seed references in `~/.config/dev-box/seed/`);
- change a seeded file that the oldest boxes adopted without a reference copy,
  so `dev-box-seed` will never update it on its own;
- change a wrapper, a symlink or a default the home relies on at login.

Adding a brand new seeded file, a new command or a new package needs no
migration: the seed and the entrypoint pick those up on the next start.

A migration catches existing homes up, it never carries the change itself. The
change goes in the seed, the `Dockerfile` or the script concerned first, so a
brand new home gets the target state straight away. The entrypoint never runs
a migration on a first start: it marks them all as played, since an empty home
has nothing to repair. A migration that is the only place where a change is
made is a bug, because new boxes will never see it.

To create one:

```bash
touch "rootfs/usr/share/devbox/migrations/$(date +%Y%m%d%H%M%S)-what-it-fixes.sh"
```

The timestamp sets the order. The script runs once, as the user, at the next
start, and `dev-box-migrate` records it in `~/.config/dev-box/migrations`.
Look at the existing migration in that directory for the shape. What it must
respect:

- idempotent: a failed run is retried, so it must survive running twice;
- harmless on a home that is already in the target state, or has nothing to
  repair: say so and exit 0, since `devbox migrate` can be run by hand at any
  time;
- never overwrite something the user may have changed. Compare against the
  shipped version or a checksum of the versions you know were shipped, and say
  out loud when nothing was touched and why;
- `$HOME` is the box's home, it never runs as root;
- English output, two spaces of indent;
- exit non-zero only when the repair genuinely failed.

## Where things go

| Change | Where |
|---|---|
| A package every box needs | `Dockerfile`, in the `pacman -Syu` list, with a comment saying why; check it exists on Arch Linux ARM too |
| A dev tool every box needs | `rootfs/etc/devbox/mise-config.toml` |
| A new `devbox` command | `rootfs/usr/local/bin/dev-box-<name>` with the `# devbox:` headers; nothing to register |
| A config file shipped to the home | `rootfs/etc/devbox/` plus a line in the `SEEDS` array of `dev-box-seed` and the seed table in the README |
| A new `devbox dev-env` environment | a `rootfs/usr/share/devbox/dev-envs/<name>.sh` with `details`, `install` and `uninstall` (`is_installed` when the mise config cannot tell, `is_supported` when it does not run everywhere), found on its own; `mise use -g` only (`php` from the image, `browser` and `media` through `devbox pkg` are the exceptions) |
| A change a user of the box notices | a line in the annotation of the next release tag (`git tag -a v1.7`): the workflow turns it into the GitHub release that `devbox changelog` and the next login show |
| A guide for the in-box skill | `rootfs/usr/share/devbox/skills/devbox/*.md`, listed in `SKILL.md` |

Keep existing file names and their options untouched: the README, the
`justfile` and `entrypoint.sh` call them by name.

## Conventions

- bash, `set -euo pipefail`, no `eval`, shellcheck clean:
  `shellcheck -e SC1091,SC2088 <files>` in the box, or from the host
  `docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable -e SC1091,SC2088 <files>`
- Comments, script output, README and commit messages in English, plain prose,
  no arrows and no typographic dashes.
- Commands say what they are doing and what to run next, and install nothing
  the user did not ask for. Running a command twice must not break anything.
- Update the README when a command, a variable or a seeded file changes.

## Testing

Never test against your own `dev-box` container and never write into `data/`.
Build, then start a throwaway container on a scratch directory, as described
in the *Testing without touching anything* section of `extending.md`. A single
file can be copied into it with `docker cp` to iterate, but the real check is a
fresh build followed by `devbox migrate --list` and `devbox seed --check`.

## Then

Commit, push, and on the host `just rebuild` (or `just up` when only `rootfs/`
changed).
