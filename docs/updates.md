# Updates

Nothing is updated automatically. The box looks, tells you, and waits for you
to run `devbox update` inside, or `just pull` (or the setup script again) on
the host for the image. The only exception is the migrations shipped with a
new image, see [below](#migrations).

There are two layers to update:

| What | Where | How |
| --- | --- | --- |
| the image (Arch, the `devbox` commands, the shipped config) | the host | run the setup script again, or `just pull` (published image), or `just rebuild` (local build) |
| the dotfiles, the mise tools, the seeded config | the box | `devbox update` |

## The check

A background check runs at start and every `UPDATE_CHECK_INTERVAL` seconds,
24 h by default, `0` turns it off. It only fetches metadata, all of it by git
commit hash where there is one: the dotfiles repo HEAD (`git ls-remote` against
the local clone), the dev-box repo against the version the image was built from,
`mise outdated`, the shipped config files whose version changed, and pending
migrations. What it finds goes into `~/.cache/dev-box/updates`, one line per
item. When there is nothing left, the file is removed. It installs nothing,
ever. `devbox check` runs it on the spot.

The login message folds that file into one line,
`2 updates available, run devbox update`, once per tmux session. The detail
stays one command away, in `devbox check` and in `devbox status`. With no file,
there is no such line. See [the login message](commands.md#the-login-message).

![Login in the box with a pending update, in the form this message had before it was folded into one line: an Updates available block lists the new dotfiles commit and the shipped config files that changed, followed by the devbox update reminder](screenshots/updates-motd.png)

## Updating inside the box

```bash
devbox update            # on a terminal: a menu; otherwise all of the below
devbox update all        # all of the below
devbox update dotfiles   # dotarchy-sync
devbox update tools      # mise install, then mise upgrade
devbox update seed       # shipped config (see customization.md)
```

`dev-box-update` is the binary and keeps working under that name. `devbox
update` is the form to remember, and `just update [what]` runs it from the
host. Migrations are separate, see below.

It clears the flag and re-runs the check when it is done.

![A full devbox update run: dotarchy-sync updates the repo and copies the config, mise installs and upgrades the tools, then the shipped config is checked](screenshots/dev-box-update.png)

`devbox update tools` is the only thing that bumps a tool version. A start
never does: it only reinstalls what is missing (`MISE_INSTALL_ON_START`).
`devbox update seed` never overwrites a shipped file you changed, it tells you
and prints the `devbox seed --force` command (see
[customization.md](customization.md#seeded-files-and-devbox-seed)).

## The image

The one item the box cannot act on is the image itself. That line points to
`just pull` for the published image, `just rebuild` for a local build, on the
host. With an install made by the setup script, running the setup script again
does the same as `just pull` and also refreshes `compose.yaml` and the other
shipped files (see [manual-install.md](manual-install.md#running-it-again-updating)).

The published image records its tag. The box compares it with the newest `v*`
tag of the repository, with `git ls-remote`, at start and once a day: a newer
release shows up in the login line and in `devbox status`, with `just pull` to
run on the host. `devbox check --image` asks the question on the spot, and
`devbox changelog --upcoming` reads the changelog of that release in the repo,
to see what it brings before pulling. A local build is compared with the head
of its branch instead, and asks for `just rebuild`.

The image learns its commit at build time: `just` passes it as a build
argument, and a bare `docker compose build` reads it from the clone the build
runs in. Only a build from a context without `.git` (a tarball) records
`unknown`, and that check is then skipped. `just status` on the host makes the
same comparison: the published image against the newest release tag of
`origin`, a local build against the local checkout:

![just status on the host: the container state from docker compose ps, the healthcheck status, and the image commit compared to the local checkout](screenshots/just-status.png)

For a private fork, the in-box check needs a `GITHUB_TOKEN` that can read the
repo.

## The changelog at login

The first login after an update starts with what changed: the releases this
home has not seen yet, three at most, one line each (the first line of their
notes). The changelog is the list of GitHub releases of the repo, one per `v*`
tag, written in the annotation of the tag. `devbox check` keeps them in
`~/.cache/dev-box/releases.md`, so the login reads a file and never the
network; `devbox changelog` reads them live, and `devbox changelog --upcoming`
shows the releases after the image the box runs. The version whose notes were
last shown is kept in `~/.config/dev-box/changelog-seen`, so the next logins
stay on the single line until the box runs a newer release. A brand new home
starts with everything marked as seen.

```
New in the box
  v1.7  2026-09-23  dev environments, one script each; Android SDK and Flutter
  v1.6  2026-09-23  Image check follow-ups
  v1.5  2026-09-23  Is this image the latest?
devbox changelog for the details
```

How a release is published is in
[architecture.md](architecture.md#publishing-a-release).

## Migrations

A new image sometimes needs a one-off repair in an existing home, something the
seed cannot pick up on its own. Those repairs are shipped as migrations, small
scripts in `/usr/share/devbox/migrations/` named after a timestamp. They run as
your user, once each, in order, and the names already played are recorded in
`~/.config/dev-box/migrations`.

```bash
devbox migrate              # on a terminal: a menu; otherwise run what is pending
devbox migrate --run        # run what is pending, no menu
devbox migrate --pending    # list it without doing anything
devbox migrate --list       # all of them, played or pending
```

This is the one thing the box does on its own at start, because a migration
comes with the image that needs it: the entrypoint runs `dev-box-migrate` right
after the seed. The first start of a brand new box marks every migration as
played without running any, since there is nothing to repair in an empty home.
A migration that fails stops the run, the ones behind it stay pending, and
`devbox migrate` tries again.
