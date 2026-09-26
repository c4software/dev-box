# dev-box

An always-on development box in a Docker container. It runs Arch Linux, it is
reachable only through Tailscale SSH (Headscale works too) or, if you prefer, a
plain SSH port, it applies the
[dotarchy/common-no-omarchy](https://github.com/c4software/dotarchy/tree/main/common-no-omarchy)
config as-is, and its dev tools are managed by [mise](https://mise.jdx.dev/).

- SSH lands you in zsh inside a tmux session named after the box, in your home.
- One command, `devbox`, gathers everything the box can do for you: language
  environments, databases, packages that survive a rebuild, your coding agent.
- Your home and your projects live on the host, in `data/`, and survive every
  image update.
- Nothing updates behind your back: a check every 24 h, a line at login, and
  `devbox update` when you decide.

![A tmux session in the box: devbox serve 3000 publishes a dev server on the tailnet and prints its URL, devbox serve off stops it, and devbox agent shows the Claude Code limit windows as bars with a countdown to the reset](docs/screenshots/serve-and-agent.jpg)

A step by step guide in French, written for students, with videos of the install and
of a first Laravel and Python project, lives on
[cours.brosseau.ovh](https://cours.brosseau.ovh/cheatsheets/dev-box/).

## Quick start

You need Docker with the Compose plugin (Docker Desktop on macOS and Windows).
Then, on the machine that will host the box:

```bash
curl -fsSL https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh | sh
```

or, without curl:

```bash
wget -qO- https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh | sh
```

The script asks a few questions (user, Tailscale or SSH access, dev
environments, podman), writes `~/dev-box/.env`, pulls the published image and
starts the box. With Tailscale and no auth key, it prints the login URL to open
once to attach the box to your tailnet. The first start then installs the
tools in the background, a few minutes.

To ask nothing, give the answers as options after `sh -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh \
  | sh -s -- --yes --access ssh --ssh-key ~/.ssh/id_ed25519.pub --dev-envs "node python"
```

`sh setup.sh --help` lists every option; they are described in
[docs/manual-install.md](docs/manual-install.md#options), together with the
install from a clone of this repository.

**Windows**: run the command inside WSL 2 (Ubuntu, with the Docker Desktop WSL
integration on), and keep the install directory in the Linux home, not under
`/mnt/c`.

## Connecting

```bash
ssh dev@dev-box                          # Tailscale, from any machine of your tailnet
ssh -p 2222 dev@127.0.0.1                # SSH access (--access ssh), from the host
docker exec -it -u dev dev-box zsh -l    # always works, on the host
```

`ssh -t dev@dev-box env NO_TMUX=1 zsh` gives a shell without tmux. Headscale
policies, `devbox serve` to reach a dev server, and Taildrop are in
[docs/access.md](docs/access.md).

## The devbox command

`devbox` alone opens a menu of everything; each command also opens its own
menu when called without arguments.

| Command | Does |
| --- | --- |
| `devbox status` | what the box is doing right now |
| `devbox dev-env node python` | install language environments through mise (`--list` for all of them) |
| `devbox dbs postgres` | start a development database (needs podman) |
| `devbox pkg add htop` | a pacman package that survives an image rebuild |
| `devbox agent` | run, pick or read the usage of your coding agent (Claude Code, Codex, pi, omp, opencode) |
| `devbox update` | update the dotfiles, the mise tools and the shipped config |
| `devbox override` | what this box changes from the image defaults, and how to undo it; `--diff [path]` shows the changes in the files |
| `devbox diagnostic ["problem"]` | starts your coding agent on the box's diagnostic guide: gathers facts with read-only commands, says what is wrong, asks before changing anything; `--report` prints the facts without an agent, to paste to someone |
| `devbox tour` | a guided tour of the box, two minutes |

The full list is in [docs/commands.md](docs/commands.md).

## Updating

- **The image**, on the host: run the setup command again. It refreshes
  `compose.yaml` and the other shipped files, pulls the latest image and
  restarts the box. It never touches `.env`, `compose.override.yaml` or
  `data/`; a shipped file you edited by hand is kept, and the new version lands
  next to it as `<file>.new`. `docker compose pull && docker compose up -d`
  does the same without refreshing the files.
- **Inside the box**: `devbox update` for the dotfiles, the mise tools and the
  shipped config.

Nothing of this happens on its own. The box checks once a day and says so at
login when an update is waiting, a new image included; `devbox check` looks on
the spot, `devbox changelog --upcoming` shows what the next image brings. See
[docs/updates.md](docs/updates.md).

## Uninstalling

```bash
cd ~/dev-box && docker compose down --rmi all
```

then delete `~/dev-box`. That deletes your home and your projects in `data/`,
so [back them up](docs/backup.md) first if you need them. Some files there
belong to root: on Linux, `sudo rm -rf ~/dev-box`.

## Documentation

- [Installing](docs/manual-install.md): setup script options, install from a
  clone, the prebuilt image, Raspberry Pi, the `just` host commands
- [Customizing](docs/customization.md): `.env` settings,
  `compose.override.yaml`, dotfiles overrides, seeded files, your own dev
  environments and wrappers, `devbox override`
- [Commands](docs/commands.md): every `devbox` command, the tour, the login
  message
- [Access](docs/access.md): Tailscale, Headscale, SSH without Tailscale,
  `devbox serve`, Taildrop
- [Terminal](docs/terminal.md): clipboard, `xdg-open`, the yazi file manager,
  notifications
- [Tools and packages](docs/tools.md): pacman, `devbox tui`, `devbox pkg`, mise
- [Dev environments](docs/dev-envs.md): `devbox dev-env` and `DEV_ENVS`
- [Containers](docs/containers.md): rootless podman and `docker` inside the box
- [Databases](docs/databases.md): `devbox dbs`
- [Coding agents](docs/agents.md): `devbox agent`, usage, the agent skill
- [Updates](docs/updates.md): the check, `devbox update`, the image, the
  changelog, migrations
- [Backup and restore](docs/backup.md): what persists, `scripts/backup.sh`,
  `scripts/restore.sh`
- [Troubleshooting](docs/troubleshooting.md): `devbox diagnostic`, logs, common
  problems
- [Architecture and contributing](docs/architecture.md): design choices,
  releases, and pointers to [AGENTS.md](AGENTS.md) and
  [extending.md](rootfs/usr/share/devbox/skills/devbox/extending.md)
