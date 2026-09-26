# Installing: setup script, clone, prebuilt image

There are two ways to install a box:

- **The setup script**, `setup.sh`: no clone, no build. It downloads the few
  files needed to run the published image and starts it. This is the Quick
  start of the [README](../README.md), and the reference for its options is
  below.
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
- `zstd` for `just backup` and `just restore`.
- [just](https://just.systems) is optional: `sudo pacman -S just` on Arch,
  `mise use -g just` anywhere else (it is not in apt). Without it, run the
  `docker compose` commands by hand.
- **Windows**: run everything inside WSL 2 (Ubuntu, with the Docker Desktop WSL
  integration on), with the install directory in the Linux home. Git Bash works
  but puts `data/` on the Windows file system, which is slow through Docker
  Desktop and loses the Unix file permissions; a directory under `/mnt/c/` from
  WSL is slow too. The setup script warns in both cases.

The image is published for amd64 and arm64.

## The setup script

```bash
curl -fsSL https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh | sh
wget -qO- https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh | sh
```

It needs only a POSIX `sh`, `curl` or `wget`, and Docker with the Compose
plugin. It checks those first, and says what to install or start when one is
missing (Docker not installed, Compose plugin missing, daemon not answering,
permission denied on the socket).

What it does on a new install:

1. asks for the install directory, `~/dev-box` by default, and refuses a
   non-empty directory that holds no box, or a clone of the repository (which
   builds its own image: use `docker compose up -d --build` there);
2. downloads `compose.yaml`, `.env.example`, `compose.override.example.yaml`,
   `scripts/backup.sh` and `scripts/restore.sh` into it;
3. asks a few questions (user, timezone, Tailscale or SSH access, hostname,
   control server, auth key or public key, GitHub token, dev environments,
   podman), each one with a default in brackets;
4. writes `.env` from `.env.example` with those answers, mode 600, with
   `DEVBOX_IMAGE` set to `ghcr.io/c4software/dev-box:latest`, so the stock
   `compose.yaml` pulls instead of building;
5. when podman was asked for, writes a `compose.override.yaml` with the podman
   block, unless one already exists (then it says to add the block by hand);
6. creates `data/home`, `data/tailscale` and the projects directory as you,
   rather than letting Docker create them as root;
7. pulls the image and starts the box with `docker compose up -d`;
8. with Tailscale and no auth key, waits up to two minutes for the login URL
   and prints it, to open once;
9. prints how to connect and the commands to run in that directory.

The first start then seeds the home, syncs the dotfiles and installs the tools
in the background: a few minutes before everything is there.

In the install directory, the box is driven with `docker compose` directly
(`docker compose logs -f`, `docker compose pull && docker compose up -d`), and
`scripts/backup.sh` and `scripts/restore.sh` handle backups. The `justfile`
belongs to the clone and build path below.

### Options

Every question can be answered in advance, as a flag or as an environment
variable. `--yes` takes the defaults for everything not given and asks
nothing; without a terminal (a pipe with no `/dev/tty`) it asks nothing either.
Under `curl | sh`, the options go after `sh -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh \
  | sh -s -- --yes --access ssh --ssh-key ~/.ssh/id_ed25519.pub
```

`sh setup.sh --help` prints the current list:

| Option | Variable | Meaning |
| --- | --- | --- |
| `--dir DIR` | `DEVBOX_DIR` | install directory, default `~/dev-box` |
| `--user NAME` | `DEVBOX_USER` | Unix user inside the box, default `dev` |
| `--access MODE` | `DEVBOX_ACCESS` | `tailscale` (default) or `ssh` |
| `--hostname NAME` | `DEVBOX_HOSTNAME` | Tailscale hostname, default `dev-box` |
| `--login-server URL` | `DEVBOX_LOGIN_SERVER` | Tailscale control server, or your Headscale |
| `--authkey KEY` | `DEVBOX_AUTHKEY` | Tailscale auth key; empty prints a login URL |
| `--ssh-key KEY\|FILE` | `DEVBOX_SSH_KEY` | public key(s) for `--access ssh`, a key or a `.pub` file; default the first of `~/.ssh/id_{ed25519,ecdsa,rsa}.pub` |
| `--ssh-port PORT` | `DEVBOX_SSH_PORT` | host port for `--access ssh`, default `2222` |
| `--ssh-bind ADDR` | `DEVBOX_SSH_BIND` | host address for it, default `127.0.0.1` (`0.0.0.0`: the LAN) |
| `--tz ZONE` | `DEVBOX_TZ` | timezone, default the host's |
| `--projects-dir DIR` | `DEVBOX_PROJECTS_DIR` | host directory mounted at `~/projets`, default `./data/projets` |
| `--github-token TOKEN` | `DEVBOX_GITHUB_TOKEN` | GitHub token with no scope, recommended |
| `--dev-envs "A B"` | `DEVBOX_DEV_ENVS` | `devbox dev-env` names installed at first start, e.g. `"node python"` |
| `--podman`, `--no-podman` | `DEVBOX_PODMAN=yes\|no` | rootless podman inside the box, off by default: it loosens the isolation of the container |
| `--image IMAGE` | `DEVBOX_IMAGE` | image to run, default `ghcr.io/c4software/dev-box:latest` |
| `--ref REF` | `DEVBOX_REF` | branch or tag of the repo to take the files from, default `main` |
| `--base-url URL\|DIR` | `DEVBOX_BASE_URL` | where to take the files from instead of GitHub (a local directory works, for testing) |
| `--no-start` | `DEVBOX_NO_START=1` | write the files, pull and start nothing |
| `-y`, `--yes` | `DEVBOX_YES=1` | ask nothing, take the defaults |
| `-h`, `--help` | | the help |

Everything it writes can be changed later in `.env`, followed by
`docker compose up -d` (see [customization.md](customization.md)).

### Running it again: updating

On a directory that already has a `.env`, the script updates instead of
installing: it refreshes the shipped files, pulls the image named by
`DEVBOX_IMAGE` in `.env` and restarts the box. It never touches `.env`,
`compose.override.yaml` or `data/`.

A shipped file is only replaced when the installed copy is still the one the
script wrote (it keeps their checksums in `.setup-shipped`). A file you edited
by hand is kept, and the new version lands next to it as `<file>.new`, to merge
by hand.

Other cases it handles:

- an empty `DEVBOX_IMAGE` in `.env` is refused, since that directory has no
  `Dockerfile` to build from;
- a `data/home` left over from an earlier install whose `.env` is gone is
  reused, nothing in it is erased (it asks first on a terminal);
- `compose.yaml` names the container `dev-box`, so only one such box runs per
  host: a container of that name started from another directory (a clone) is
  refused, with the directory it comes from.

The same update by hand, in the install directory:

```bash
docker compose pull && docker compose up -d    # or: just pull
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
   docker compose up -d --build     # or: just up
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

A GitHub workflow (`.github/workflows/build.yml`) builds the image when a `v*`
tag is pushed, and only then, and publishes it on `ghcr.io/c4software/dev-box`
for amd64 and arm64 (native runners, one manifest), always as `latest` and
under no other tag. A push on `main` publishes nothing: a release is a
deliberate act, `git tag -a v0.3.0 && git push origin v0.3.0`. Each run starts
from a fresh base with no layer cache, the same as `just rebuild`, so nothing
is ever frozen at a previous build.

To run it instead of building locally, set the image in `.env` (the setup
script does this for you):

```bash
DEVBOX_IMAGE=ghcr.io/c4software/dev-box:latest
```

`just up` and `just rebuild` then pull instead of building, `just pull` does the
same on purpose, and the `Dockerfile` is never run on the host. Everything else
in `.env` applies unchanged: it is read by Compose at run time, not at build
time, so the user, the volumes, Tailscale, the dotfiles and the dev
environments are exactly as customisable on the published image as on a local
build. The image has no idea which `.env` will run it. It is a plain rolling
Arch: `just pull` fetches whatever the last workflow run produced, no more
often than you decide.

The published image records its tag, and the box tells you when a newer
release exists (see [updates.md](updates.md#the-image)).

The Pi is the main beneficiary: pulling takes a minute where building takes
tens of them. Leave `DEVBOX_IMAGE` empty to keep building from your own clone,
which is the only way to run a change that is not on `main` yet.

## Raspberry Pi 5 (arm64)

The image builds and runs on arm64 as it does on amd64.
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
requirements listed at the top of this page. `just` is not in apt: use
`mise use -g just`, or run the `docker compose` commands by hand.

Building on the Pi takes a while, because of `base-devel`, neovim and
tree-sitter. Expect the first build to be measured in tens of minutes, not
minutes. The published image avoids it.

## Host commands

A `justfile` at the root wraps the Compose invocations you would otherwise type
by hand. Run `just` to list everything:

| Command | Does |
| --- | --- |
| `just up` | Build if needed (or pull with `DEVBOX_IMAGE`) and start the box |
| `just rebuild` | Update Arch: rebuild from a fresh base image (or pull), then restart |
| `just pull` | Pull the published image (`DEVBOX_IMAGE` in `.env`) and restart on it |
| `just down` | Stop and remove the container (`./data/` is kept) |
| `just restart` | Restart without rebuilding |
| `just logs` | Follow the entrypoint logs (last 100 lines) |
| `just status` | Container state, healthcheck, and whether the image lags the repo |
| `just shell` | `zsh -l` inside the box, as your user |
| `just ssh` | SSH in, through Tailscale or the published port |
| `just update [what]` | Run `dev-box-update` in the box, same as `devbox update` (`dotfiles`, `tools`, `seed`, `all`) |
| `just backup [dest]` | Write a backup archive (see [backup.md](backup.md)) |
| `just restore <archive>` | Restore one |

![Output of just --list on the host, showing the available recipes with their descriptions](screenshots/just-list.png)

Use `just rebuild` when Arch moves. It runs
`docker compose build --pull --no-cache`. `--pull` alone is not enough: as long
as the base image keeps the same digest, the `pacman -Syu` layer stays cached
and the packages remain frozen at the date of the first build.

The recipes read `.env`, so `just shell` and `just ssh` follow `USER_NAME`,
`TS_HOSTNAME`, `TS_DISABLE`, `SSH_BIND` and `SSH_PORT` without extra
configuration.
