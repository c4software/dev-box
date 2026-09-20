# Updates

Nothing updates on its own. That is a design choice, not an oversight. The box
looks, tells you, and waits.

## The check

`dev-box-check-updates` (`devbox check`) runs at start and then every
`UPDATE_CHECK_INTERVAL` seconds, 24 h by default, `0` turns it off. It only
fetches metadata, and every call is bounded by a timeout so a slow network
cannot hold up a login. It installs nothing, ever.

It compares four things:

1. **dotfiles**: the HEAD of the local clone against the remote branch, with
   `git ls-remote`. No object is pulled.
2. **the image**: `DEVBOX_COMMIT` from `/etc/devbox/release`, burned in at build
   time, against the HEAD of the dev-box repository. This one is only known when
   the image was built through `just`, which passes the commit as a build
   argument; a bare `docker compose build` records `unknown` and the check is
   skipped.
3. **mise tools**: `mise outdated`.
4. **the shipped config**: `dev-box-seed --check`.

What it finds goes into `~/.cache/dev-box/updates`, one line per item. When
there is nothing left, the file is deleted.

## The login message

Interactive shells source `/etc/devbox/updates-motd.sh`. If the flag file
exists it is printed once per tmux session, followed by a reminder to run
`devbox update`. With no flag file the cost is a single file test.

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
`MISE_INSTALL_ON_START=true` it only reinstalls what is missing.

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
