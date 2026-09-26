# Updates

Nothing is updated automatically. The box looks, tells you, and waits for you
to run `devbox update` inside, or the setup script again on the host for
the image. The only exception is the migrations shipped with a
new image, see [below](#migrations).

There are two layers to update:

| What | Where | How |
| --- | --- | --- |
| the image (Arch, the `devbox` commands, the shipped config) | the host | run the setup script again (published image), or `docker compose pull && docker compose up -d`; rebuild the container for a local build |
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
update` is the form to remember. Migrations are separate, see below.

It clears the flag and re-runs the check when it is done.

![A full devbox update run: dotarchy-sync updates the repo and copies the config, mise installs and upgrades the tools, then the shipped config is checked](screenshots/dev-box-update.png)

`devbox update tools` is the only thing that bumps a tool version. A start
never does: it only reinstalls what is missing (`MISE_INSTALL_ON_START`).
`devbox update seed` never overwrites a shipped file you changed, it tells you
and prints the `devbox seed --force` command (see
[customization.md](customization.md#seeded-files-and-devbox-seed)).

## The image

The one item the box cannot act on is the image itself. That line says to pull
the image and restart the container for the published image, or to rebuild
the container for a local build, on the host. With an install made by the setup script, running the setup script again
does the same as `docker compose pull && docker compose up -d` and also refreshes `compose.yaml` and the other
shipped files (see [manual-install.md](manual-install.md#running-it-again-updating)).

The published image records its tag. The box compares it with the newest `v*`
tag of the repository, with `git ls-remote`, at start and once a day: a newer
release shows up in the login line and in `devbox status`, with the pull to run
on the host. The arm64 image records the same tag (`v1.12`, published as
`v1.12-arm64`) and names `latest-arm64` as the image to pull, but it is built
by hand after the release (see
[Publishing a release](architecture.md#publishing-a-release)): an arm64 box
compares itself with the newest `-arm64` tag of the registry instead
(`ghcr.io`, read anonymously), so it only reports a release whose arm64 image
exists. When the registry cannot be read, it falls back on the tags of the
repository and says the arm64 image may not be published yet.

`devbox check --image` asks the question on the spot, and
`devbox changelog --upcoming` reads the changelog of that release in the repo,
to see what it brings before pulling. A local build is compared with the head
of its branch instead, and asks for a rebuild.

An arm64 box that runs the amd64 image (`latest`, emulated) is told at login,
in `devbox status` and in `devbox check`, with the `DEVBOX_IMAGE=...:latest-arm64`
line to put in `.env` on the host. An arm64 box installed before the images
were split per architecture, when `latest` held both, cannot know about the
split: the notes of the release that made it (`devbox changelog --upcoming`)
and the setup script, run again on the host, say to change `DEVBOX_IMAGE`
before pulling (see [manual-install.md](manual-install.md#prebuilt-image)).

The image learns its commit at build time: `docker compose build` reads it from the clone the build
runs in. Only a build from a context without `.git` (a tarball) records
`unknown`, and that check is then skipped.

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
