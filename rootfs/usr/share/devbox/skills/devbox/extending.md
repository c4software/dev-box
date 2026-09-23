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

Two cases, as with dev tools.

- A package every box should have: the `Dockerfile`, in the `pacman -Syu` list.
  Keep it alphabetically near its neighbours and say in a comment what calls
  for it. Check the package exists on Arch Linux ARM as well, since the box
  also builds for arm64 (Raspberry Pi 5) from a different base image. A package
  that only exists on x86_64 breaks the Pi build.
- A package only this box needs: `devbox pkg add <package>`. It is installed by
  pacman now and reinstalled at every start from
  `~/.config/dev-box/packages`, so it survives a rebuild without a commit.
  Nothing else does: a config file edited in `/etc` is not tracked.

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

One file, `rootfs/usr/share/devbox/dev-envs/<name>.sh`, found on its own:
nothing to register, the file name is the environment name. It defines
functions and runs nothing at the top level:

```bash
# shellcheck shell=bash
# devbox dev-env <name>: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
<Short description, shown by the menu and --list>

<The long text of --info: what it installs, what a removal leaves in place.>
TXT
}

install() { mise use -g <tool>@latest; }

uninstall() {
  unuse <tool>
  log "~/<data dir> is left in place."
}
```

`is_installed` is optional: without it, the environment is installed when the
tool `<name>` is declared in the global mise config. Define it when that is not
true (a tool under another name, a composer package, a pacman package).
`is_supported` is optional too: when the environment cannot run on every
machine (x86_64 only, say), it prints the reason on one line and exits 1.
The environment then disappears from the menu and `--list`, a direct install
refuses it with the reason, and `--if-missing` (`DEV_ENVS`) skips it, so one
`.env` can serve an amd64 box and an arm64 one:

```bash
is_supported() {
  [ "$(uname -m)" = "x86_64" ] && return 0
  echo "<vendor> publishes linux x86_64 builds only"
  return 1
}
``` Each
function runs in its own bash process with `set -euo pipefail`, and can call
the helpers of `rootfs/usr/share/devbox/lib/dev-env.sh`: `log`, `err`,
`declared`, `unuse`, and `dev_env install <other>` for an environment this one
sits on (`laravel` on `php` and `node`).

Only `mise use -g` and `mise unuse -g`: no pacman, no `curl | sh`. That is the
whole point of the command. The removal takes out what the environment brought
and nothing more: no project data, and not a base another environment may rely
on (say in the message how to remove it). PHP is the one exception, baked into
the image through the `Dockerfile` because mise would have to compile it; OCaml
is not in it for the same reason.

The same file dropped in `~/.config/dev-box/dev-envs/` of a box adds an
environment to that box only, or replaces the image's one of the same name:
handy to try a new one before shipping it.

### A new devbox command

A `rootfs/usr/local/bin/dev-box-<name>` script whose first lines carry the
headers `devbox` reads:

```bash
#!/usr/bin/env bash
# devbox:name=<name>
# devbox:summary=<one line, English, no final period>
# devbox:args=[a|b|c]
# devbox:hidden=true     # only if it is not a user-facing command
# devbox:requires=tailscale   # hidden while the feature is off (tailscale, podman)
```

There is nothing to register anywhere. `devbox` finds it on the next start.
Keep the existing file names and their options untouched: the README, the
`justfile` and `entrypoint.sh` call them by name.

### A migration for existing boxes

Some changes cannot reach a home that already exists. The seed only updates a
file the user never touched, and it has no reference copy at all on the oldest
boxes. That is what migrations are for: a script shipped with the image, run
once, as the user, that repairs the home.

```bash
touch "rootfs/usr/share/devbox/migrations/$(date +%Y%m%d%H%M%S)-what-it-fixes.sh"
```

The name starts with a timestamp, which is what sets the order, and ends with a
few words saying what it does. The template:

```bash
#!/usr/bin/env bash
# One paragraph saying what this repairs, and for which boxes.
set -euo pipefail

TARGET="$HOME/.config/something"

if [ ! -f "$TARGET" ]; then
  echo "  nothing to repair here"
  exit 0
fi
...
```

Rules that matter:

- Idempotent. It runs once in practice, but a failed run is retried, so it must
  survive being run twice.
- Never overwrite something the user may have changed. Compare against the
  shipped version, or a checksum of the versions you know you shipped
  (`git log -p -- rootfs/etc/devbox/<file>` finds them), and say out loud why
  nothing was touched when that is the answer.
- It runs as the user, not as root. `$HOME` is the box's home.
- Output in English, two spaces of indent, since `dev-box-migrate` prints the
  name of the migration above it.
- Exit non-zero only when the repair genuinely failed. That stops the run and
  leaves the migrations behind it pending.

Nothing to register: `dev-box-migrate` picks up every `.sh` of that directory,
and the entrypoint runs it at the next start.

### A config file shipped to the home

Put the file under `rootfs/etc/devbox/` and add a
`<source>:<path relative to the home>` line to the `SEEDS` array of
`rootfs/usr/local/bin/dev-box-seed`. Then add it to the seed table in the
README. `dev-box-seed` takes care of the rest: laid down if missing, updated if
untouched, never overwritten if the user changed it.

### Release notes

The changelog of the box is the list of GitHub releases of the repo. A change a
user of the box notices goes in the annotation of the next release tag: a
subject line, then one short line per change saying what it does and what to
run.

```bash
git tag -a v1.7        # the editor opens: the notes
git push origin v1.7
```

The first line is what the login shows, next to the tag: make it a summary
(a leading `v1.7: ` is dropped). The workflow builds the image, then creates
the release with that text.
`devbox check` saves the notes in the box, and the first login after `just
pull` shows them. A release edited on GitHub afterwards is picked up at the next
check. Keep Markdown headings out of the notes: they are flattened.

### A guide in this skill

A new `.md` file in `rootfs/usr/share/devbox/skills/devbox/`, and a line for it
in the "Topic Guides" list of `SKILL.md`. Nothing else: the skill directory is
linked into the home, so the guide is there on the next start.

## Conventions

- bash, `set -euo pipefail`, no `eval`.
- shellcheck clean: `shellcheck -e SC1091,SC2088 <files>` in the box (declared
  in the seeded mise config), or from the host:
  `docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable -e SC1091,SC2088 <files>`
- Comments and script output in English, plain prose, no arrows and no
  typographic dashes. Same for the README.
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

docker logs -f devbox-test          # wait for "mise: tools installed"
docker exec -u dev devbox-test zsh -lc 'devbox --help'
docker exec -u dev devbox-test env -u TS_DISABLE zsh -lc 'devbox migrate --list'
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
