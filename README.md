# dev-box

An always-on development box in a Docker container: Arch Linux, reachable only
through Tailscale SSH (works with Headscale), with the
[dotarchy/common-no-omarchy](https://github.com/c4software/dotarchy/tree/main/common-no-omarchy)
config applied as-is and dev tools managed by [mise](https://mise.jdx.dev/).

- `tailscaled` runs inside the container and Tailscale SSH opens the shell; nothing
  is published on the host. Without Tailscale (`TS_DISABLE=true`), the box falls back
  to its own OpenSSH server on a published port, public key only.
- SSH lands you in zsh inside a tmux session named after the box (`TS_HOSTNAME`,
  `dev-box` by default), in your home directory.
- Dotfiles pulled from a git repo, applied without running its install scripts.
- Nothing updates behind your back: a background check every 24 h, a message at
  login, and `dev-box-update` when you decide.
- Two persistent volumes (home and projects) that survive image rebuilds.
- System packages via pacman (image), dev tools via mise (home).

## Quick start

1. Create `.env` from the example and fill in at least `TS_LOGIN_SERVER` and
   (recommended) `GITHUB_TOKEN`:

   ```bash
   cp .env.example .env
   ```

2. Build and start:

   ```bash
   docker compose up -d --build
   docker compose logs -f
   ```

   The logs print the login URL to open to attach the box to your tailnet.

3. From any machine on your tailnet:

   ```bash
   ssh dev@dev-box
   ```

Machine-specific settings (extra volumes, resource limits) go in a local override
that Compose merges automatically and git ignores:

```bash
cp compose.override.example.yaml compose.override.yaml
```

### Raspberry Pi 5 (arm64)

The image builds and runs on arm64 as it does on amd64: `docker compose up -d --build`
picks the right base by itself. On the Pi, `archlinux:latest` is replaced by the
community image `menci/archlinuxarm:base` (Arch Linux ARM, rebuilt daily) — a
third-party base, not an official Arch one, which is the price of arm64 here.
`mise` is not packaged for Arch Linux ARM either, so the build falls back to the
official installer from `mise.run`; everything else comes from pacman as usual.

On the host:

- Docker >= 24 with Compose v2 (`docker compose version`); Raspberry Pi OS 64-bit.
- `/dev/net/tun` present (stock kernel: it is).
- `zstd` for `just backup` / `just restore`.
- `just` is not in apt: `mise use -g just`, or run the `docker compose` commands
  by hand.

Building on the Pi takes a while (`base-devel`, neovim, tree-sitter): expect the
first build to be measured in tens of minutes, not minutes.

## Host commands

A `justfile` at the root wraps the Compose invocations you would otherwise type
by hand. Install [just](https://just.systems) (`sudo pacman -S just` on Arch,
`mise use -g just` anywhere else), then run `just` to list everything:

| Command | Does |
|---|---|
| `just up` | Build if needed and start the box |
| `just rebuild` | Update Arch: rebuild from a fresh base image, then restart |
| `just down` | Stop and remove the container (`./data/` is kept) |
| `just restart` | Restart without rebuilding |
| `just logs` | Follow the entrypoint logs (last 100 lines) |
| `just status` | Container state, healthcheck, and whether the image lags the repo |
| `just shell` | `zsh -l` inside the box, as your user |
| `just ssh` | SSH in, through Tailscale or the published port |
| `just update [what]` | Run `dev-box-update` in the box (`dotfiles`, `tools`, `seed`, `all`) |
| `just backup [dest]` | Write a backup archive (see *Backup*) |
| `just restore <archive>` | Restore one |

`just rebuild` is the one to reach for when Arch moves: it runs
`docker compose build --pull --no-cache`. `--pull` alone is not enough: as long as
the base image keeps the same digest, the `pacman -Syu` layer stays cached and the
packages remain frozen at the date of the first build.

The recipes read `.env`, so `just shell` and `just ssh` follow `USER_NAME`,
`TS_HOSTNAME`, `TS_DISABLE`, `SSH_BIND` and `SSH_PORT` without extra configuration.

## Configuration

All settings live in `.env` (see `.env.example`):

| Variable | Default | Meaning |
|---|---|---|
| `USER_NAME` | `dev` | Unix user inside the box (UID/GID fixed at 1000:1000) |
| `USER_SHELL` | `/bin/zsh` | Login shell |
| `TZ` | `Europe/Paris` | Timezone |
| `PROJECTS_DIR` | `./data/projets` | Host directory mounted at `~/projets` (separate from the home) |
| `TS_HOSTNAME` | `dev-box` | Tailscale hostname; also the container hostname and the tmux session name |
| `TS_LOGIN_SERVER` | `https://headscale.example.com` | Control server; empty = Tailscale's own |
| `TS_AUTHKEY` | empty | Auth key; empty = the login URL is printed in the logs |
| `TS_EXTRA_ARGS` | empty | Extra arguments appended to `tailscale up` |
| `TS_DISABLE` | `false` | `true` = no Tailscale, the box runs its own sshd instead |
| `SSH_AUTHORIZED_KEYS` | empty | Public key(s) allowed when `TS_DISABLE=true`, one per line |
| `SSH_BIND` | `127.0.0.1` | Host interface the SSH port is published on |
| `SSH_PORT` | `2222` | Host port mapped to the box's port 22 |
| `DOTARCHY_REPO` | `https://github.com/c4software/dotarchy.git` | Dotfiles repo |
| `DOTARCHY_BRANCH` | `main` | Branch to track |
| `DOTARCHY_SUBDIR` | `common-no-omarchy` | Subfolder holding `config/`, `default/`, `install/` |
| `UPDATE_CHECK_INTERVAL` | `86400` | Update *check* period in seconds (`0` = off); it installs nothing |
| `PODMAN_ENABLE` | `false` | Start the rootless podman socket at boot; needs the podman block of `compose.override.example.yaml` |
| `MISE_INSTALL_ON_START` | `true` | Reinstall missing mise tools in the background at start (no version bump) |
| `GITHUB_TOKEN` | empty | Token with no scopes, avoids GitHub API rate limits during mise installs |
| `LLM_PROXY_URL` | `http://llmproxy` | Endpoint used by the `llm-proxy.ts` extension of pi/omp |
| `LLM_PROXY_API_KEY` | `unused` | Its API key |

`compose.yaml` already carries what the box needs from the host: `/dev/net/tun` plus
the `NET_ADMIN` and `NET_RAW` capabilities for `tailscaled`. No `privileged`, no host
Docker socket. Rootless podman needs more (see *Containers inside the box*) and is
therefore opt-in.

## Headscale setup

On first start the box prints a login URL in `docker compose logs -f`: open it (or
feed it to `headscale nodes register`) to attach the machine. The node identity is then
kept in `./data/tailscale`, so this happens only once.

Tailscale SSH is refused without an `ssh` rule in the policy, and the `ssh` rule alone
does not open the network: as soon as the policy contains `grants` or `acls`, traffic to
the box must be allowed too, otherwise port 22 is filtered. Policy validated with
Headscale v0.29.3 (`headscale policy check`):

```json
{
  "grants": [
    { "src": ["alice@"], "dst": ["alice@"], "ip": ["*"] }
  ],
  "ssh": [
    { "action": "accept", "src": ["alice@"], "dst": ["alice@"], "users": ["dev"] }
  ]
}
```

- `src` / `dst`: the Headscale user owning the machines (the one the box was
  registered to).
- `users`: the Unix account inside the box (`USER_NAME`).
- A `user@` SSH destination requires `src` to contain only that same user.

## SSH without Tailscale

Set `TS_DISABLE=true` in `.env` and the box starts its own OpenSSH server instead of
`tailscaled`. Public key only — password and root login are refused:

```bash
TS_DISABLE=true
SSH_AUTHORIZED_KEYS="ssh-ed25519 AAAA... you@laptop"
SSH_BIND=127.0.0.1   # 0.0.0.0 to expose it on the LAN
SSH_PORT=2222
```

```bash
ssh -p 2222 dev@127.0.0.1
```

The keys are rewritten into `~/.ssh/authorized_keys` at every start, so `.env` is the
source of truth. Host keys are generated once into `~/.config/dev-box/ssh` and live in
the persistent home: no "host key changed" warning after a rebuild.

With `SSH_AUTHORIZED_KEYS` empty, sshd is not started at all (the container stays up
and reports unhealthy) — use `docker exec -it -u dev dev-box zsh -l`.

## Connecting

```bash
ssh dev@dev-box
```

The login shell runs `exec tmux new-session -A -s "$(hostname)" -c ~`: you always land
in the same tmux session, named after the box, starting in your home directory. Running
several boxes side by side therefore gives each one a session of its own. To get a plain
shell instead:

```bash
ssh -t dev@dev-box env NO_TMUX=1 zsh
```

The user is created at container start (if missing) with UID/GID 1000:1000, zsh as
shell and passwordless sudo. The home itself is persistent.

## Dotfiles sync

`dotarchy-sync` clones (or updates) the dotfiles repo into `~/.local/share/dotarchy`
and takes **only the config**. It never runs the repo's install scripts.

- `config/` → `~/.config/` (zsh, tmux, starship, lazygit, btop, ...), except `nvim`.
- `default/{zshrc,bashrc,profile}` → `~/.zshrc`, `~/.bashrc`, `~/.profile`.
- `config/nvim` is a LazyVim overlay: it is applied on top of the official LazyVim
  starter and rebuilt on each pass. `lazy-lock.json` belongs to the box and is kept.
  A pre-existing `~/.config/nvim` not managed by the sync is renamed to `.bak.<timestamp>`.
- `try` and `proj` (used by the `p` alias and the `Ctrl+F` widget) are downloaded into
  `~/.local/bin` from the URLs found in `install/bootstrap.sh`, so any tool added to
  the repo the same way is picked up automatically.
- Git aliases (`co`, `br`, `ci`, `st`, `s`, `pull.rebase`, ...) come from the `setup`
  function of `install/git.sh` (only `git config --global` calls).
- tmux is reloaded if it is running.

It runs on the very first start, then only when you ask for it: `dotarchy-sync` (or
`dev-box-update dotfiles`). There is no periodic sync.

Edit the config **in the repo**, not in the box: copied files are overwritten on every
pass. For box-only tweaks, put them in `~/.config/dev-box/overrides/`, a mirror of the
home (`overrides/.config/tmux/tmux.conf` → `~/.config/tmux/tmux.conf`): they are
re-applied at the end of every sync, after the steps that overwrite (nvim included).

Not replicated: the rest of `bootstrap.sh` (keyboard layout, shell choice) and
`install/nvim.sh`. Its tweaks (`relativenumber = false`, `gb` → `<C-^>`) only apply
here if they live in `config/nvim`.

## Tools

**pacman (image).** Everything the common-no-omarchy config and `try`/`proj` call
(zsh, tmux, mise, gum, starship, zoxide, fzf, eza, bat, ripgrep, fd, lazygit, jq,
neovim, luarocks, tree-sitter-cli), the base (tailscale, rsync, base-devel, ...) and
rootless podman (see *Containers inside the box*).

- Update Arch: `docker compose build --pull && docker compose up -d`.
- A `sudo pacman -S` inside the box is lost on rebuild: add the package to the
  `Dockerfile` instead.

**mise (persistent home).** Dev tools declared in `~/.config/mise/config.toml`:

- `node` (LTS)
- `claude` (Claude Code, `aqua:anthropics/claude-code`)
- `pi` (`aqua:earendil-works/pi`)
- `omp` (`github:can1357/oh-my-pi`, via mise's github backend)

`claude`, `pi`, `omp` and `opencode` are wrapped in `/usr/local/bin`: each wrapper runs
`mise use -g <tool>` (a no-op once declared) then `mise x <tool> -- <cmd>`, so the
command works on first call even before the background install finished, or after
the tool was removed from `~/.config/mise/config.toml`. `opencode` is not
pre-installed: its first call installs it.

They are installed in the background on first start; follow progress with
`tail -f ~/.cache/dev-box-install.log`. Later starts only reinstall what is missing
(`MISE_INSTALL_ON_START`), never bump a version. Upgrading is explicit:
`dev-box-update tools` runs `mise install` then `mise upgrade`. Add more on demand,
e.g. `mise use -g go@latest`. Set `GITHUB_TOKEN` (no scopes needed) to avoid GitHub
API rate limits.


### Containers inside the box

`docker run`, `docker build` and `docker compose` can work inside the box, without
the host's Docker socket and without a privileged container. What answers is
[podman](https://podman.io/) running rootless as your user. It is **off by
default**, because nesting it forces the box's own isolation open: the seccomp
profile, the read-only `/proc/sys` and AppArmor all have to be lifted for the
container, which makes a container-to-host escape easier than it is otherwise.
To turn it on:

1. uncomment the podman block (`/dev/fuse` and the three `security_opt`) in
   `compose.override.example.yaml`, copied to `compose.override.yaml`;
2. set `PODMAN_ENABLE=true` in `.env`;
3. `just up`.

Then:

- `podman-docker` provides `/usr/bin/docker` as a shim over the `podman` CLI;
- the entrypoint starts `podman system service` as your user on
  `/run/user/1000/podman/podman.sock`, and login shells export
  `DOCKER_HOST=unix:///run/user/1000/podman/podman.sock`, so Compose v2 (the
  `docker-compose` package, a real Docker plugin) and anything else that talks to
  the socket finds it;
- images live in `~/.local/share/containers`, in the persistent home — and outside
  the backup, they re-pull.

```bash
docker run --rm alpine echo ok
docker build -t mine .
docker compose up -d && docker compose ps
```

With `PODMAN_ENABLE=false` no socket is started and `DOCKER_HOST` is not set.
`docker` and `podman` then go through a wrapper that stops with the three steps
above instead of an obscure error; the same wrapper points to
`~/.cache/dev-box-podman.log` when podman is enabled but the socket never came
up. `PODMAN_FORCE=1 docker …` (or `/usr/bin/podman`) bypasses it.

Known limits:

- Containers started here are rootless: no `--privileged` inside the box,
  publishing a port below 1024 is refused (it would need
  `net.ipv4.ip_unprivileged_port_start` lowered), and UIDs are mapped — a file
  written as root in a container belongs to `100000` on the host side of the
  bind mount.
- Networking goes through pasta/slirp4netns rather than a host bridge. Published
  ports are reachable from inside the box (`curl localhost:8080`); reaching them
  from your laptop means going through the box's own address (Tailscale).
- Storage uses `fuse-overlayfs`, since overlayfs cannot always stack on the
  overlay the box itself runs on: correct everywhere, slower than native overlay
  on heavy I/O.
- Docker on the host still owns the box itself: `just up`, `just rebuild` and
  friends run on the host, not in here.

## Agent configuration

A base config is shipped in the image and laid down in the home by `dev-box-seed`
(run at every start, and by `dev-box-update seed`). A reference copy of what was laid
down is kept in `~/.config/dev-box/seed/<path>`, which gives three cases per file:

- **missing** → the shipped file is copied and recorded as the reference;
- **untouched** (identical to the reference) and the shipped version changed → it is
  updated in place (`conf mise à jour : ~/x`);
- **modified locally** and the shipped version changed → nothing is overwritten, the
  box tells you the new version exists and how to take it:
  `dev-box-seed --force ~/x`.

A box created before the reference existed simply adopts the shipped version as its
reference on the next start, without overwriting anything.

| File | From |
|---|---|
| `~/.claude/settings.json` | `rootfs/etc/devbox/claude/settings.json` |
| `~/.claude/agents/{pi,omp}.md` | `rootfs/etc/devbox/claude/agents/` |
| `~/.pi/agent/extensions/llm-proxy.ts` | `rootfs/etc/devbox/llm-proxy.ts` |
| `~/.omp/agent/extensions/llm-proxy.ts` | same file |
| `~/.config/mise/config.toml` | `rootfs/etc/devbox/mise-config.toml` |

- `settings.json`: theme, effort level, empty commit/PR attribution, and the
  `harness@c4software` plugin from its GitHub marketplace. No `model` key: Claude Code
  picks its own default. Claude Code rewrites this file by itself, so it goes to
  "modified locally" almost immediately — that is expected; a new shipped version is
  reported, never forced.
- `pi.md` / `omp.md`: Claude Code sub-agents that delegate a task to the `pi` and `omp`
  CLIs. They only run when asked for explicitly.
- `llm-proxy.ts` registers the Albert (DINUM) provider in pi and omp. It reads
  `LLM_PROXY_URL` and `LLM_PROXY_API_KEY` from `.env`; if the endpoint is unreachable it
  registers nothing rather than blocking startup.

Login shells get those two variables from `/etc/devbox/env`, written at start and
sourced by `/etc/devbox/zshenv`: neither Tailscale SSH nor sshd inherits the
environment of PID 1.

## Updates

Nothing is updated automatically. A background check runs at start and every
`UPDATE_CHECK_INTERVAL` seconds (24 h by default, `0` = off) and only fetches
metadata, all of it by git commit hash where there is one: the dotfiles repo HEAD
(`git ls-remote` against the local clone), the dev-box repo HEAD against the commit
the image was built from, `mise outdated`, and the shipped config files whose
version changed. What it finds goes into `~/.cache/dev-box/updates`
(one line per item); when there is nothing left, the file is removed.

Interactive shells print that file at login — once per tmux session — followed by
`→ dev-box-update`. With no file, the cost is a single file test.

```bash
dev-box-update            # all of the below
dev-box-update dotfiles   # dotarchy-sync
dev-box-update tools      # mise install, then mise upgrade
dev-box-update seed       # shipped config (see above)
```

It clears the flag and re-runs the check when it is done. The one item it cannot
act on is the image itself: that line points to `just rebuild` (or `just up`) on the
host. The image knows its commit only when built through `just`, which passes it as
a build argument; a bare `docker compose build` records `unknown` and that check is
skipped. A private dev-box repo is only reachable from the box if `GITHUB_TOKEN`
can read it; otherwise `just status` on the host makes the same comparison, image
commit against the local checkout.

## Persistence

Three bind mounts under `./data/` (git-ignored); a rebuild of the image loses nothing:

| Host | Container | Contents |
|---|---|---|
| `./data/home` | `~` | config, mise toolchains, nvim plugins, pi/omp sessions, zsh history, SSH host keys, podman images |
| `${PROJECTS_DIR:-./data/projets}` | `~/projets` | your repositories |
| `./data/tailscale` | `/var/lib/tailscale` | tailscaled state (node identity) |

`~/projets` is a separate volume so it can be backed up, shared or pointed at another
disk independently. Only its top-level directory is ever chowned (when Docker created
it as root); its contents are never touched. You can start from a fresh home
(`rm -rf data/home`) without affecting your projects.

## Backup

`scripts/backup.sh [--with-tailscale] [dest_dir]` (also `just backup`) writes
`dev-box-<TS_HOSTNAME>-<YYYYmmdd-HHMMSS>.tar.zst` into `dest_dir`, `./backups`
by default (git-ignored). It needs `zstd` on the host.

What goes in:

- `data/home`, minus the caches that rebuild themselves: `.cache`,
  `.local/share/{mise,nvim,dotarchy,lazyvim-starter}`, `.local/state/nvim`,
  `.npm`, `.bun`, and `.local/share/containers` (the podman image store: bulky,
  re-pullable, and full of files owned by mapped UIDs).
- The projects directory (`PROJECTS_DIR`), minus every `node_modules`.
  `.git/objects` is **kept**: your repositories come back whole, with their history.
- A copy of `.env` and `compose.override.yaml` when they exist. `.env` holds
  `TS_AUTHKEY` and `GITHUB_TOKEN`: treat the archive as a secret.

What stays out: `data/tailscale`. It holds the node identity, and restoring it
elsewhere would give you two machines claiming the same one. Pass
`--with-tailscale` if you really want it in the archive.

Ownership is preserved (`--numeric-owner`), and `sudo` is used only when
something that goes into the archive is not readable as you. The archive is read
back end to end after being written, and its entry count and size are printed.

Restoring:

```bash
./scripts/restore.sh backups/dev-box-dev-box-20260920-101500.tar.zst
# or: just restore backups/dev-box-dev-box-20260920-101500.tar.zst
```

It stops the container, lists what already exists and would be overwritten, asks
for confirmation, then unpacks at the root of the repo. Files are overwritten one
by one: nothing outside the archive is ever deleted, so a home restored over a
newer one keeps whatever the archive does not mention. Add `--yes` to skip the
prompt; outside a terminal the script refuses to run without it. Then bring the
box back with `just up`: the mise toolchains were not in the archive, the start
reinstalls them (or run `just update tools`).

If `PROJECTS_DIR` points outside the repo (another disk), the projects are stored
under `projets-external/` in the archive and restored there: move them back
yourself, the script will not write outside the repo.

## Troubleshooting and debug

- **Run without Tailscale.** See *SSH without Tailscale* above. With no
  `SSH_AUTHORIZED_KEYS` set, sshd does not start (the container stays up and reports
  unhealthy); get in with `docker exec -it -u dev dev-box zsh -l`.
- **Logs.** `docker compose logs -f` shows the entrypoint, `dotarchy-sync`, `dev-box-seed`
  and `tailscale up` output (including the login URL when `TS_AUTHKEY` is empty).
- **mise install failed.** See `~/.cache/dev-box-install.log`; rate-limit errors
  usually mean `GITHUB_TOKEN` is missing.
- **SSH refused / port 22 filtered.** Check the Headscale policy: both the `ssh` rule
  and a `grants`/`acls` rule allowing traffic to the box are required.
- **Healthcheck.** Every 60 s: `tailscale status --peers=false`, or a connection to
  port 22 when `TS_DISABLE=true`.
- **`docker` says it cannot reach the API.** The podman socket did not start: see
  `~/.cache/dev-box-podman.log`, and check `PODMAN_ENABLE` and the podman block
  of `compose.override.yaml`.

## Design choices

- **No host Docker socket.** Mounting it would amount to root on the host. When
  containers are needed inside the box, rootless podman with the `docker` shim
  answers instead, as an opt-in: it costs part of the box's own isolation, so the
  default keeps the container as tight as Docker makes it.
- **Tailscale inside the container.** The box is only reachable from the tailnet;
  nothing is published on the host, and Tailscale SSH handles authentication.
- **amd64 and arm64.** The official `archlinux` image exists only for x86_64, so
  arm64 builds (Raspberry Pi 5) use Arch Linux ARM through the community image
  `menci/archlinuxarm:base`, rebuilt daily. BuildKit picks the base from
  `TARGETARCH`; the rest of the image assumes nothing about the architecture.
- **Fixed UID/GID 1000:1000.** Same owner as on the host for the bind-mounted volumes.
