# Updates

Nothing updates on its own, apart from the migrations shipped with the image
(see below). That is a design choice, not an oversight. The box looks, tells
you, and waits.

## The check

`dev-box-check-updates` (`devbox check`) runs at start and then every
`UPDATE_CHECK_INTERVAL` seconds, 24 h by default, `0` turns it off. It only
fetches metadata, and every call is bounded by a timeout so a slow network
cannot hold up a login. It installs nothing, ever.

It compares five things:

1. **dotfiles**: the HEAD of the local clone against the remote branch, with
   `git ls-remote`. No object is pulled.
2. **the image**: `DEVBOX_COMMIT` from `/etc/devbox/release`, burned in at build
   time, against the HEAD of the dev-box repository. This one is only known when
   the image was built through `just`, which passes the commit as a build
   argument; a bare `docker compose build` records `unknown` and the check is
   skipped.
3. **mise tools**: `mise outdated`.
4. **the shipped config**: `dev-box-seed --check`.
5. **pending migrations**: `dev-box-migrate --pending`. The start runs them, so
   this line only shows up when one failed or was acknowledged by hand.

What it finds goes into `~/.cache/dev-box/updates`, one line per item. When
there is nothing left, the file is deleted.

## The login message

Interactive shells source `/etc/devbox/updates-motd.sh`, which calls
`dev-box-motd` once per tmux session, and once per shell outside tmux. It
folds the flag file into one line, `2 updates available, run devbox update`.
The detail of what is waiting stays in `devbox check` and `devbox status`. A
second flag, `~/.cache/dev-box/dev-envs`, gives one more line while the
`DEV_ENVS` environments install at start, or when that failed.
With no flag file there is no such line. The message itself is covered in
`commands.md`, under `motd`.

## Migrations, the one exception

Migrations are the only thing the box runs on its own. They are small scripts
in `/usr/share/devbox/migrations/`, shipped with the image, that repair an
existing home after a change the seed cannot pick up by itself. The entrypoint
runs `dev-box-migrate` at every start, as your user, right after the seed. That
is deliberate: a migration arrives with the image that needs it, so there is
nothing to decide.

Each one runs once. The names already played are listed in
`~/.config/dev-box/migrations`. A brand new home has all of them marked as
played without running any, since an empty home has nothing to repair. A
migration that fails stops the run; the ones behind it stay pending and are
tried again on the next start or on `devbox migrate`.

```bash
devbox migrate --list             # all of them, played or pending
devbox migrate --pending          # what is left
devbox migrate                    # run it now
devbox migrate --mark-done <name> # acknowledge one without running it
```

Nothing else in the box is automatic: no package is upgraded, no tool is
bumped, no dotfile is pulled without you asking.

## Updating

```bash
devbox update            # all of the below
devbox update dotfiles   # dotarchy-sync
devbox update tools      # mise install, then mise upgrade
devbox update seed       # the config shipped by the image
```

It clears the flag and re-runs the check when it is done, so a login right
after an update is quiet.

`devbox update tools` is the only thing that bumps a version. `mise install`
fetches what is declared and missing; `mise upgrade` moves the tools pinned to
`latest` forward. A start never bumps a version: with
`MISE_INSTALL_ON_START=true` it only reinstalls what is missing, and the
`DEV_ENVS` environments of `.env` are only installed when they are missing
(`dev-box-dev-env --if-missing`, output in `~/.cache/dev-box/dev-envs.log`).

mise keeps a minimum release age of 24 h by default, so a release published
this morning is not picked up yet. That is deliberate quarantine against a bad
or compromised release. The tool wrappers (`claude`, `pi`, `omp`, `codex`,
`opencode`) and `dev-box-dev-env` set `MISE_MINIMUM_RELEASE_AGE=0`, because
asking for a tool by name means asking for it now.

## The shipped config

`devbox update seed` never overwrites a file you changed. When the shipped
version moved and your copy differs from the reference in
`~/.config/dev-box/seed/`, the box only tells you, and prints the command to
take the new version:

```bash
dev-box-seed --force ~/.claude/settings.json    # one file
devbox seed --force                             # all of them
```

`~/.claude/settings.json` is the usual one: Claude Code rewrites it by itself,
so it counts as modified almost immediately. A new shipped version will always
be reported and never forced. That is expected, not a bug.

## What the box cannot update

The image itself. That line in the flag points at `just rebuild` on the host.
From inside the box there is nothing to do about it, and no amount of `sudo
pacman -Syu` will help: those packages are gone on the next rebuild anyway.

`just status` on the host makes the same image comparison, and `devbox status`
shows the commit the running image was built from.
