# mise-box

An always-on development box in a Docker container: Arch Linux, reachable only
through Tailscale SSH (works with Headscale), with the
[dotarchy/common-no-omarchy](https://github.com/c4software/dotarchy/tree/main/common-no-omarchy)
config applied as-is and dev tools managed by [mise](https://mise.jdx.dev/).

- No published ports, no OpenSSH server: `tailscaled` runs inside the container and
  Tailscale SSH opens the shell.
- SSH lands you in zsh inside a tmux session (`Work`), in `~/projets`.
- Dotfiles pulled from a git repo and kept in sync, without running its install scripts.
- Two persistent volumes (home and projects) that survive image rebuilds.
- System packages via pacman (image), dev tools via mise (home).

## Quick start

1. Create `.env` from the example and fill in at least `TS_LOGIN_SERVER`, `TS_AUTHKEY`
   and (recommended) `GITHUB_TOKEN`:

   ```bash
   cp .env.example .env
   ```

2. Build and start:

   ```bash
   docker compose up -d --build
   docker compose logs -f
   ```

3. From any machine on your tailnet:

   ```bash
   ssh dev@devbox
   ```

Machine-specific settings (extra volumes, resource limits) go in a local override
that Compose merges automatically and git ignores:

```bash
cp compose.override.example.yaml compose.override.yaml
```

## Configuration

All settings live in `.env` (see `.env.example`):

| Variable | Default | Meaning |
|---|---|---|
| `USER_NAME` | `dev` | Unix user inside the box (UID/GID fixed at 1000:1000) |
| `USER_SHELL` | `/bin/zsh` | Login shell |
| `TZ` | `Europe/Paris` | Timezone |
| `PROJECTS_DIR` | `./data/projets` | Host directory mounted at `~/projets` (separate from the home) |
| `TS_HOSTNAME` | `devbox` | Tailscale hostname (also the container hostname) |
| `TS_LOGIN_SERVER` | `https://headscale.example.com` | Control server; empty = Tailscale's own |
| `TS_AUTHKEY` | empty | Pre-auth key; empty = interactive login (see logs) |
| `TS_EXTRA_ARGS` | empty | Extra arguments appended to `tailscale up` |
| `TS_DISABLE` | `false` | `true` = no Tailscale, access via `docker exec` only |
| `DOTARCHY_REPO` | `https://github.com/c4software/dotarchy.git` | Dotfiles repo |
| `DOTARCHY_BRANCH` | `main` | Branch to track |
| `DOTARCHY_SUBDIR` | `common-no-omarchy` | Subfolder holding `config/`, `default/`, `install/` |
| `DOTARCHY_SYNC_INTERVAL` | `3600` | Re-sync period in seconds (`0` = at start and manually only) |
| `MISE_INSTALL_ON_START` | `true` | Install mise tools in the background at start |
| `GITHUB_TOKEN` | empty | Token with no scopes, avoids GitHub API rate limits during mise installs |

The container needs `/dev/net/tun` plus the `NET_ADMIN` and `NET_RAW` capabilities
(already set in `compose.yaml`).

## Headscale setup

Create a pre-auth key (`--user` takes the numeric ID, see `headscale users list`):

```bash
headscale preauthkeys create --user <ID> --reusable --expiration 24h
```

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

- `src` / `dst`: the Headscale user owning the machines (the one the auth key was
  created for).
- `users`: the Unix account inside the box (`USER_NAME`).
- A `user@` SSH destination requires `src` to contain only that same user.

## Connecting

```bash
ssh dev@devbox
```

The login shell runs `exec tmux new-session -A -s Work -c ~/projets`: you always land
in the same tmux session, in `~/projets`. To get a plain shell instead:

```bash
ssh -t dev@devbox env NO_TMUX=1 zsh
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

It runs at start, every `DOTARCHY_SYNC_INTERVAL` seconds (default 1 h, `0` = off), or
manually with `dotarchy-sync`.

Edit the config **in the repo**, not in the box: copied files are overwritten on every
pass.

Not replicated: the rest of `bootstrap.sh` (keyboard layout, shell choice) and
`install/nvim.sh`. Its tweaks (`relativenumber = false`, `gb` → `<C-^>`) only apply
here if they live in `config/nvim`.

## Tools

**pacman (image).** Everything the common-no-omarchy config and `try`/`proj` call
(zsh, tmux, mise, gum, starship, zoxide, fzf, eza, bat, ripgrep, fd, lazygit, jq,
neovim, luarocks, tree-sitter-cli) plus the base (tailscale, rsync, base-devel, ...).

- Update Arch: `docker compose build --pull && docker compose up -d`.
- A `sudo pacman -S` inside the box is lost on rebuild: add the package to the
  `Dockerfile` instead.

**mise (persistent home).** Dev tools declared in `~/.config/mise/config.toml`:

- `node` (LTS)
- `pi` (`npm:@earendil-works/pi-coding-agent`)
- `omp` (`github:can1357/oh-my-pi`, via mise's github backend)

They are installed in the background at start; follow progress with
`tail -f ~/.cache/mise-box-install.log`. Add more on demand, e.g.
`mise use -g go@latest`. Set `GITHUB_TOKEN` (no scopes needed) to avoid GitHub API
rate limits.

## Persistence

Three bind mounts under `./data/` (git-ignored); a rebuild of the image loses nothing:

| Host | Container | Contents |
|---|---|---|
| `./data/home` | `~` | config, mise toolchains, nvim plugins, pi/omp sessions, zsh history |
| `${PROJECTS_DIR:-./data/projets}` | `~/projets` | your repositories |
| `./data/tailscale` | `/var/lib/tailscale` | tailscaled state (node identity) |

`~/projets` is a separate volume so it can be backed up, shared or pointed at another
disk independently. Only its top-level directory is ever chowned (when Docker created
it as root); its contents are never touched. You can start from a fresh home
(`rm -rf data/home`) without affecting your projects.

## Troubleshooting and debug

- **Run without Tailscale.** Set `TS_DISABLE=true` in `.env`, then enter with
  `docker exec -it -u dev dev-box zsh -l`. The healthcheck stays healthy in this mode.
- **Logs.** `docker compose logs -f` shows the entrypoint, `dotarchy-sync` and
  `tailscale up` output (including the login URL when `TS_AUTHKEY` is empty).
- **mise install failed.** See `~/.cache/mise-box-install.log`; rate-limit errors
  usually mean `GITHUB_TOKEN` is missing.
- **SSH refused / port 22 filtered.** Check the Headscale policy: both the `ssh` rule
  and a `grants`/`acls` rule allowing traffic to the box are required.
- **Healthcheck.** `tailscale status --peers=false` every 60 s (skipped when
  `TS_DISABLE=true`).

## Design choices

- **No Docker inside the box.** No client, no host socket, on purpose: access to the
  host's Docker socket amounts to root on the host.
- **Tailscale inside the container.** The box is only reachable from the tailnet;
  nothing is published on the host, and Tailscale SSH handles authentication.
- **x86_64 only.** The official `archlinux` image exists only for x86_64.
- **Fixed UID/GID 1000:1000.** Same owner as on the host for the bind-mounted volumes.
