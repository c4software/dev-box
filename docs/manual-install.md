# Installing: setup script, clone, prebuilt image

There are two ways to install a box:

- **The setup script**, `setup.sh`: no clone, no build. It downloads the few
  files needed to run the published image and starts it. This is the Quick
  start of the [README](../README.md), and its questions are listed below.
- **A clone of the repository**, built locally or running the published image.
  This is the way to change the box itself, or to run a change that is not
  released yet.

## Host requirements

- Docker >= 24 with the Compose v2 plugin (`docker compose version`). The old
  standalone `docker-compose` is not enough. On macOS and Windows, Docker
  Desktop ships both.
- The user running the install must be able to reach Docker without `sudo`
  (the `docker` group on Linux). With `sudo`, the box would land in root's home.
- `/dev/net/tun` present, which is the case on stock kernels, Raspberry Pi OS
  included.
- `zstd` for `scripts/backup.sh` and `scripts/restore.sh`.
- **Windows**: run everything inside WSL 2 (Ubuntu, with the Docker Desktop WSL
  integration on), with the install directory in the Linux home. Git Bash works
  but puts `data/` on the Windows file system, which is slow through Docker
  Desktop and loses the Unix file permissions; a directory under `/mnt/c/` from
  WSL is slow too. The setup script warns in both cases.

The image is published for amd64 (`ghcr.io/c4software/dev-box:latest`) and
arm64 (`ghcr.io/c4software/dev-box:latest-arm64`, a Raspberry Pi 5 or a Mac
with Apple silicon), as two separate images: see [Prebuilt image](#prebuilt-image).

## The setup script

```bash
curl -fsSL https://cours.brosseau.ovh/devbox.sh | sh
wget -qO- https://cours.brosseau.ovh/devbox.sh | sh
```

The short address redirects to
`https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh`, the
`setup.sh` at the root of this repository; both work.

Piping a download into a shell is a bad habit, even though it is the usual
one-liner: it runs code you have not read, and a download cut halfway runs a
truncated script. The better way is to download it first, read it, then run
it:

```bash
curl -fsSLo devbox.sh https://cours.brosseau.ovh/devbox.sh   # or: wget -O devbox.sh ...
less devbox.sh
sh devbox.sh
```

It takes no option: it asks its questions on the terminal, and refuses to run
without one. It needs only a POSIX `sh`, `curl` or `wget`, and Docker with the
Compose plugin. It checks those first, and says what to install or start when
one is missing (Docker not installed, Compose plugin missing, daemon not
answering, permission denied on the socket). When
[gum](https://github.com/charmbracelet/gum) is installed, the questions use it
(a list to pick the access from, a yes or no toggle); otherwise they are plain
prompts. Ctrl-C at any question stops the setup.

What it does on a new install:

1. asks for the install directory, `~/dev-box` by default, and refuses a
   non-empty directory that holds no box, or a clone of the repository (which
   builds its own image: use `docker compose up -d --build` there);
2. downloads `compose.yaml`, `.env.example`, `compose.override.example.yaml`,
   `scripts/backup.sh` and `scripts/restore.sh` into it;
3. asks the [questions](#the-questions), each one with a default;
4. writes `.env` from `.env.example` with those answers, mode 600, with
   `DEVBOX_IMAGE` set to the image of the machine, chosen from `uname -m`:
   `ghcr.io/c4software/dev-box:latest` on x86_64,
   `ghcr.io/c4software/dev-box:latest-arm64` on aarch64 (any other machine is
   refused), so the stock `compose.yaml` pulls instead of building;
5. when podman was asked for, writes a `compose.override.yaml` with the podman
   block, unless one already exists (then it says to add the block by hand);
6. creates `data/home`, `data/tailscale` and the projects directory as you,
   rather than letting Docker create them as root;
7. asks whether to pull the image and start the box now (yes by default):
   yes runs `docker compose pull` and `docker compose up -d`, no prints those
   two commands to run later;
8. with Tailscale and no auth key, waits up to two minutes for the login URL
   and prints it, to open once;
9. prints how to connect and the commands to run in that directory;
10. opens a new shell in the install directory (a script cannot move the shell
    that ran it); `exit` goes back to where you were.

The first start then seeds the home, syncs the dotfiles and installs the tools
in the background: a few minutes before everything is there.

In the install directory, the box is driven with `docker compose` directly
(`docker compose logs -f`, `docker compose pull && docker compose up -d`), and
`scripts/backup.sh` and `scripts/restore.sh` handle backups (see
[Host commands](#host-commands)).

### The questions

In this order, with their default. Enter keeps the default.

| Question | Default | Written to `.env` |
| --- | --- | --- |
| Install directory | `~/dev-box` | nothing, it is where everything goes |
| Unix user inside the box | `dev` | `USER_NAME` (lowercase letters, digits, `_` and `-`; asked again otherwise) |
| Timezone | the host's | `TZ` |
| Language of the box | the host's locale (`LC_ALL`, `LC_MESSAGES`, `LANG`, on macOS the system language), else `C.UTF-8` | `LANG`: `xx_YY.UTF-8` or `C.UTF-8`, asked again otherwise. `fr_FR.UTF-8` puts the `devbox` menu and the login tips in French, see [Language](customization.md#language) |
| Access: `tailscale` or `ssh` | `tailscale` | `TS_DISABLE` (`false` for Tailscale, `true` for SSH) |
| Tailscale hostname of the box (Tailscale only) | `dev-box` | `TS_HOSTNAME` |
| Control server (Tailscale only) | `https://controlplane.tailscale.com` | `TS_LOGIN_SERVER`: your Headscale URL, or Tailscale |
| Tailscale auth key (Tailscale only, hidden) | none | `TS_AUTHKEY`; without one, a login URL is printed to open once |
| GitHub user whose public keys are allowed in (SSH only) | none | `SSH_AUTHORIZED_KEYS`: the keys published at `https://github.com/USER.keys`; asked again if the account has none |
| Public key of this machine allowed in (SSH only) | the first of `~/.ssh/id_{ed25519,ecdsa,rsa}.pub` | `SSH_AUTHORIZED_KEYS`, added to the GitHub keys: a `.pub` file or the key itself; empty (when `~/.ssh` holds none) skips it. With no key at all, sshd does not start |
| Add another key? (SSH only), asked until no | no | `SSH_AUTHORIZED_KEYS`, added to the others: a `.pub` file, the key itself, or `github:USER`; another machine, another account |
| SSH port on this host (SSH only) | `2222` | `SSH_PORT` |
| Address the SSH port listens on (SSH only): `127.0.0.1` or `0.0.0.0` | `127.0.0.1` | `SSH_BIND`: `127.0.0.1` is this machine only, `0.0.0.0` the LAN too |
| GitHub token (hidden) | none | `GITHUB_TOKEN`: a token with no scope, recommended, avoids the GitHub API rate limit while tools install |
| Dev environments | none | `DEV_ENVS`: `devbox dev-env` names installed at the first start, space separated, e.g. `node python` |
| Turn podman on? | no | `PODMAN_ENABLE`, plus a `compose.override.yaml` with the podman block (see [containers.md](containers.md)): it loosens the isolation of the container |
| Pull the image and start the box now? | yes | nothing |

A key, a GitHub user or a port that is not valid is refused with the reason,
and the question is asked again. `.env` also gets
`DEVBOX_IMAGE=ghcr.io/c4software/dev-box:latest` (x86_64) or
`DEVBOX_IMAGE=ghcr.io/c4software/dev-box:latest-arm64` (arm64); everything else keeps the
value of `.env.example`, `PROJECTS_DIR` included. An existing install is not
asked anything: its `.env` is left alone, so the box stays in English until
`LANG` is added to it.

Everything it writes can be changed later in `.env`, followed by
`docker compose up -d` (see [customization.md](customization.md)).

### Running it again: updating

On a directory that already has a `.env`, the script updates instead of
installing: it refreshes the shipped files, then asks "Pull the latest image
and restart the box?" (yes by default), which pulls the image named by
`DEVBOX_IMAGE` in `.env` and restarts the box; no leaves it at the refreshed
files. It asks nothing else, and never touches `.env`,
`compose.override.yaml` or `data/`.

A shipped file is only replaced when the installed copy is still the one the
script wrote (it keeps their checksums in `.setup-shipped`). A file you edited
by hand is kept, and the new version lands next to it as `<file>.new`, to merge
by hand.

Other cases it handles:

- an empty `DEVBOX_IMAGE` in `.env` is refused, since that directory has no
  `Dockerfile` to build from;
- an arm64 machine whose `.env` still names `ghcr.io/c4software/dev-box:latest`
  (an install made before the images were split per architecture) gets a
  warning with the exact `DEVBOX_IMAGE=` line to put in `.env` instead, and the
  pull question defaults to no: `latest` is the amd64 image now, and does not
  run there. The same goes for an amd64 machine on `latest-arm64`;
- a `data/home` left over from an earlier install whose `.env` is gone is
  reused, nothing in it is erased (it asks first);
- `compose.yaml` names the container `dev-box`, so only one such box runs per
  host: a container of that name started from another directory (a clone) is
  refused, with the directory it comes from.

The same update by hand, in the install directory:

```bash
docker compose pull && docker compose up -d
```

### Uninstalling

```bash
cd ~/dev-box && docker compose down --rmi all
```

then delete the directory. That deletes your home and your projects in
`data/`, so take a [backup](backup.md) first if you want them. Some files there
belong to root or to mapped UIDs: on Linux, `sudo rm -rf ~/dev-box`.

## From a clone

```bash
git clone https://github.com/c4software/dev-box.git
cd dev-box
```

1. Create `.env` from the example, set `TS_LOGIN_SERVER` if you use Headscale,
   and add `GITHUB_TOKEN` (recommended):

   ```bash
   cp .env.example .env
   ```

2. Build and start:

   ```bash
   docker compose up -d --build
   docker compose logs -f
   ```

   The logs print the login URL to open to attach the box to your tailnet. To
   skip the build and run the published image instead, see
   [Prebuilt image](#prebuilt-image) below.

3. From any machine on your tailnet:

   ```bash
   ssh dev@dev-box
   ```

The first start seeds the home, syncs the dotfiles and installs the mise tools:

![Container logs of a first start: the user home is created, dev-box-seed lays down the shipped config, dotarchy-sync clones the dotfiles repo and copies config, nvim and the helper scripts](screenshots/first-boot.png)

Machine-specific settings, such as extra volumes or resource limits, go in a
local override that Compose merges automatically and git ignores (see
[customization.md](customization.md#composeoverrideyaml)):

```bash
cp compose.override.example.yaml compose.override.yaml
```

## Prebuilt image

The image is published on `ghcr.io/c4software/dev-box` as two images, one
per architecture, each built on a native GitHub runner:

| Machine | Tags | Built |
| --- | --- | --- |
| amd64 (x86_64) | `latest`, and the release tag (`v1.12`) | by `.github/workflows/build.yml`, on every `v*` tag pushed |
| arm64 (Raspberry Pi 5, Apple silicon) | `latest-arm64`, and `v1.12-arm64` | by `.github/workflows/build-arm64.yml`, by hand only |

They are not merged into one multi-arch tag: `latest` is the amd64 image only,
and an arm64 machine that pulls it is refused (`no matching manifest for
linux/arm64`). A release tag pins a version, `latest` follows the releases.
The arm64 image follows the releases later, when it is built by hand (see
[Publishing a release](architecture.md#publishing-a-release)): until then,
`latest-arm64` stays on the previous release it was built for. A push on
`main` publishes nothing: a release is a
deliberate act, `git tag -a v0.3.0 && git push origin v0.3.0`. Each run starts
from a fresh base with no layer cache, the same as
`docker compose build --pull --no-cache`, so nothing is ever frozen at a
previous build. The image is a single layer compressed with zstd, which every
Docker from 23 on and podman can pull.

To run it instead of building locally, set the image of the machine in `.env`
(the setup script does this for you):

```bash
DEVBOX_IMAGE=ghcr.io/c4software/dev-box:latest          # amd64
DEVBOX_IMAGE=ghcr.io/c4software/dev-box:latest-arm64    # arm64
```

then pull and start it with `docker compose pull && docker compose up -d`: the
`Dockerfile` is never run on the host. Everything else
in `.env` applies unchanged: it is read by Compose at run time, not at build
time, so the user, the volumes, Tailscale, the dotfiles and the dev
environments are exactly as customisable on the published image as on a local
build. The image has no idea which `.env` will run it. It is a plain rolling
Arch: `docker compose pull` fetches whatever the last workflow run produced, no
more often than you decide.

The published image records its tag, and the box tells you when a newer
release exists (see [updates.md](updates.md#the-image)).

Before these two images, `latest` held both architectures. An arm64 box
installed then still has `DEVBOX_IMAGE=ghcr.io/c4software/dev-box:latest` in
its `.env`, and must switch to `latest-arm64` before its next pull: edit the
line in `.env`, then `docker compose pull && docker compose up -d`. Running the
setup script again says so, and so does the box once it runs an image that
knows about the split. Nothing in the home changes.

The Pi is the main beneficiary: pulling takes a minute where building takes
tens of them. Leave `DEVBOX_IMAGE` empty to keep building from your own clone,
which is the only way to run a change that is not on `main` yet.

## Raspberry Pi 5 (arm64)

The image builds and runs on arm64 as it does on amd64. The published one is
`ghcr.io/c4software/dev-box:latest-arm64`, not `latest` (see
[Prebuilt image](#prebuilt-image)); the setup script picks it by itself. It is
built by hand after a release, so it may lag the amd64 image by a release or
two, and the box only reports a new arm64 image once it exists.
`docker compose up -d --build` picks the right base by itself. On the Pi,
`archlinux:latest` is replaced by the community image `menci/archlinuxarm:base`
(Arch Linux ARM, rebuilt daily). That is a third-party base, not an official
Arch one, which is the price of arm64 here. `mise` is not packaged for Arch
Linux ARM either, so the build falls back to the official installer from
`mise.run`. Everything else comes from pacman as usual.

What was actually tested: the arm64 build and first start were validated under
QEMU emulation. mise installs through the `mise.run` installer, the arm64
assets for `claude`, `pi`, `codex` and `omp` are picked automatically, and
LazyVim compiles its parsers. Rootless podman could not be tested under
emulation, because user namespaces fail under qemu-user. It still has to be
confirmed on a real Pi, together with `/dev/fuse` and the AppArmor setup of
Raspberry Pi OS.

On the host: Docker >= 24 with Compose v2 on Raspberry Pi OS 64-bit, plus the
requirements listed at the top of this page.

Building on the Pi takes a while, because of `base-devel`, neovim and
tree-sitter. Expect the first build to be measured in tens of minutes, not
minutes. The published image avoids it.

## Host commands

Everything on the host goes through `docker compose`, run in the install
directory or the clone. Compose reads `.env` by itself.

| Command | Does |
| --- | --- |
| `docker compose up -d` | Start the box, or restart it after a change to `.env` or `compose.override.yaml` |
| `docker compose up -d --build` | Build the image from the clone if needed, then start |
| `docker compose build --pull --no-cache && docker compose up -d` | Update Arch: rebuild from a fresh base image, then restart |
| `docker compose pull && docker compose up -d` | Pull the published image (`DEVBOX_IMAGE` in `.env`) and restart on it |
| `docker compose down` | Stop and remove the container (`./data/` is kept) |
| `docker compose restart` | Restart without rebuilding |
| `docker compose logs -f --tail=100` | Follow the entrypoint logs |
| `docker compose ps` | Container state and healthcheck |
| `docker exec -it -u <user> dev-box zsh -l` | A login shell inside the box, as your user |
| `scripts/backup.sh [dest]` | Write a backup archive (see [backup.md](backup.md)) |
| `scripts/restore.sh <archive>` | Restore one |

Rebuild with `--pull --no-cache` when Arch moves. `--pull` alone is not
enough: as long as the base image keeps the same digest, the `pacman -Syu`
layer stays cached and the packages remain frozen at the date of the first
build.

Updates of the dotfiles, the tools and the shipped config run inside the box
with `devbox update` (from the host,
`docker exec -u <user> dev-box dev-box-update all`). Whether the image lags
its repository is also answered inside: `devbox status` or
`devbox check --image`.
