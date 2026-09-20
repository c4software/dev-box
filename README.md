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
- Dotfiles pulled from a git repo and kept in sync, without running its install scripts.
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
| `DOTARCHY_SYNC_INTERVAL` | `3600` | Re-sync period in seconds (`0` = at start and manually only) |
| `MISE_INSTALL_ON_START` | `true` | Install mise tools in the background at start |
| `GITHUB_TOKEN` | empty | Token with no scopes, avoids GitHub API rate limits during mise installs |
| `LLM_PROXY_URL` | `http://llmproxy` | Endpoint used by the `llm-proxy.ts` extension of pi/omp |
| `LLM_PROXY_API_KEY` | `unused` | Its API key |

The container needs `/dev/net/tun` plus the `NET_ADMIN` and `NET_RAW` capabilities
(already set in `compose.yaml`).

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
- `claude` (Claude Code, `aqua:anthropics/claude-code`)
- `pi` (`aqua:earendil-works/pi`)
- `omp` (`github:can1357/oh-my-pi`, via mise's github backend)

`claude`, `pi`, `omp` and `opencode` are wrapped in `/usr/local/bin`: each wrapper runs
`mise use -g <tool>` (a no-op once declared) then `mise x <tool> -- <cmd>`, so the
command works on first call even before the background install finished, or after
the tool was removed from `~/.config/mise/config.toml`. `opencode` is not
pre-installed: its first call installs it.

They are installed in the background at start; follow progress with
`tail -f ~/.cache/dev-box-install.log`. Add more on demand, e.g.
`mise use -g go@latest`. Set `GITHUB_TOKEN` (no scopes needed) to avoid GitHub API
rate limits.


## Agent configuration

A base config is laid down in the home on first start, and never overwritten
afterwards — once there, the files belong to the box (Claude Code rewrites its own
`settings.json`). Delete a file and the next start puts the shipped one back.

| File | From |
|---|---|
| `~/.claude/settings.json` | `rootfs/etc/devbox/claude/settings.json` |
| `~/.claude/agents/{pi,omp}.md` | `rootfs/etc/devbox/claude/agents/` |
| `~/.pi/agent/extensions/llm-proxy.ts` | `rootfs/etc/devbox/llm-proxy.ts` |
| `~/.omp/agent/extensions/llm-proxy.ts` | same file |

- `settings.json`: model, theme, effort level, empty commit/PR attribution, and the
  `harness@c4software` plugin from its GitHub marketplace.
- `pi.md` / `omp.md`: Claude Code sub-agents that delegate a task to the `pi` and `omp`
  CLIs. They only run when asked for explicitly.
- `llm-proxy.ts` registers the Albert (DINUM) provider in pi and omp. It reads
  `LLM_PROXY_URL` and `LLM_PROXY_API_KEY` from `.env`; if the endpoint is unreachable it
  registers nothing rather than blocking startup.

Login shells get those two variables from `/etc/devbox/env`, written at start and
sourced by `/etc/devbox/zshenv`: neither Tailscale SSH nor sshd inherits the
environment of PID 1.

## Persistence

Three bind mounts under `./data/` (git-ignored); a rebuild of the image loses nothing:

| Host | Container | Contents |
|---|---|---|
| `./data/home` | `~` | config, mise toolchains, nvim plugins, pi/omp sessions, zsh history, SSH host keys |
| `${PROJECTS_DIR:-./data/projets}` | `~/projets` | your repositories |
| `./data/tailscale` | `/var/lib/tailscale` | tailscaled state (node identity) |

`~/projets` is a separate volume so it can be backed up, shared or pointed at another
disk independently. Only its top-level directory is ever chowned (when Docker created
it as root); its contents are never touched. You can start from a fresh home
(`rm -rf data/home`) without affecting your projects.

## Troubleshooting and debug

- **Run without Tailscale.** See *SSH without Tailscale* above. With no
  `SSH_AUTHORIZED_KEYS` set, sshd does not start (the container stays up and reports
  unhealthy); get in with `docker exec -it -u dev dev-box zsh -l`.
- **Logs.** `docker compose logs -f` shows the entrypoint, `dotarchy-sync` and
  `tailscale up` output (including the login URL when `TS_AUTHKEY` is empty).
- **mise install failed.** See `~/.cache/dev-box-install.log`; rate-limit errors
  usually mean `GITHUB_TOKEN` is missing.
- **SSH refused / port 22 filtered.** Check the Headscale policy: both the `ssh` rule
  and a `grants`/`acls` rule allowing traffic to the box are required.
- **Healthcheck.** Every 60 s: `tailscale status --peers=false`, or a connection to
  port 22 when `TS_DISABLE=true`.

## Design choices

- **No Docker inside the box.** No client, no host socket, on purpose: access to the
  host's Docker socket amounts to root on the host.
- **Tailscale inside the container.** The box is only reachable from the tailnet;
  nothing is published on the host, and Tailscale SSH handles authentication.
- **x86_64 only.** The official `archlinux` image exists only for x86_64.
- **Fixed UID/GID 1000:1000.** Same owner as on the host for the bind-mounted volumes.
