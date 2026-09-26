# Customizing the box

The image is the same for everyone. What makes a box yours lives in three
places, none of which a rebuild or a new image touches:

- on the host, `.env` and `compose.override.yaml`, read by Compose at start;
- in the home, `~/.config/dev-box/` (overrides, own dev environments, the
  packages to put back, the default agent) and the seeded config files;
- in the home too, the dotfiles, the mise config and `~/.local/bin`.

`devbox override` lists all of it in one place, see
[the last section](#reviewing-it-all-devbox-override).

A change that every box should get belongs in the repository instead, see
[architecture.md](architecture.md#contributing).

## `.env` settings

All settings live in `.env` (see `.env.example`). After a change, run
`docker compose up -d` on the host.

| Variable | Default | Meaning |
| --- | --- | --- |
| `USER_NAME` | `dev` | Unix user inside the box (UID/GID fixed at 1000:1000) |
| `USER_SHELL` | `/bin/zsh` | Login shell |
| `TZ` | `Europe/Paris` | Timezone |
| `PROJECTS_DIR` | `./data/projets` | Host directory mounted at `~/projets` (separate from the home) |
| `DEVBOX_IMAGE` | empty | Image to run instead of a local build, see [Prebuilt image](manual-install.md#prebuilt-image). The setup script sets it to `ghcr.io/c4software/dev-box:latest` |
| `TS_HOSTNAME` | `dev-box` | Tailscale hostname; also the container hostname and the tmux session name |
| `TS_LOGIN_SERVER` | `https://controlplane.tailscale.com` | Control server: Tailscale itself (the default), or your Headscale URL |
| `TS_AUTHKEY` | empty | Auth key; empty means the login URL is printed in the logs |
| `TS_EXTRA_ARGS` | empty | Extra arguments appended to `tailscale up` |
| `TS_DISABLE` | `false` | `true` means no Tailscale, the box runs its own sshd instead |
| `SSH_AUTHORIZED_KEYS` | empty | Public key(s) allowed when `TS_DISABLE=true`, one per line |
| `SSH_BIND` | `127.0.0.1` | Host interface the SSH port is published on |
| `SSH_PORT` | `2222` | Host port mapped to the box's port 22 |
| `DOTARCHY_REPO` | `https://github.com/c4software/dotarchy.git` | Dotfiles repo |
| `DOTARCHY_BRANCH` | `main` | Branch to track |
| `DOTARCHY_SUBDIR` | `common-no-omarchy` | Subfolder holding `config/`, `default/`, `install/` |
| `UPDATE_CHECK_INTERVAL` | `86400` | Update *check* period in seconds (`0` turns it off); it installs nothing |
| `PODMAN_ENABLE` | `false` | Start the rootless podman socket at boot; needs the podman block of `compose.override.example.yaml` |
| `MISE_INSTALL_ON_START` | `true` | Reinstall missing mise tools in the background at start (no version bump) |
| `DEV_ENVS` | empty | Dev environments (`devbox dev-env` names, space separated) installed at start when missing, in the background |
| `GITHUB_TOKEN` | empty | Token with no scopes, avoids GitHub API rate limits during mise installs |
| `LLM_PROXY_URL` | `http://llmproxy` | Endpoint used by the `llm-proxy.ts` extension of pi/omp |
| `LLM_PROXY_API_KEY` | `unused` | Its API key |

`compose.yaml` already carries what the box needs from the host:
`/dev/net/tun` plus the `NET_ADMIN` and `NET_RAW` capabilities for
`tailscaled`. No `privileged`, no host Docker socket. Rootless podman needs
more, see [containers.md](containers.md), and is therefore opt-in.

Login shells get `LLM_PROXY_URL`, `LLM_PROXY_API_KEY` and the other variables
the box needs from `/etc/devbox/env`, written at start and sourced by
`/etc/devbox/zshenv`. Neither Tailscale SSH nor sshd inherits the environment
of PID 1.

## `compose.override.yaml`

Machine-specific settings go in a local override that Compose merges with
`compose.yaml` automatically, and that git ignores:

```bash
cp compose.override.example.yaml compose.override.yaml
```

The example is empty by default, with commented blocks for extra volumes
(say `/srv/partage:/home/dev/partage`), resource limits (`mem_limit`, `cpus`),
and rootless podman (`/dev/fuse` and three `security_opt`, see
[containers.md](containers.md)). It is also the place to publish a port of the
box on the host. Neither the setup script nor a rebuild ever touches it.

## Dotfiles sync and overrides

`dotarchy-sync` clones or updates the dotfiles repo into
`~/.local/share/dotarchy` and takes only the config. It never runs the repo's
install scripts.

| Source in the repo | Destination in the home |
| --- | --- |
| `config/` (zsh, tmux, starship, lazygit, btop, ...), except `nvim` | `~/.config/` |
| `default/zshrc`, `default/bashrc`, `default/profile` | `~/.zshrc`, `~/.bashrc`, `~/.profile` |

- `config/nvim` is a LazyVim overlay. It is applied on top of the official
  LazyVim starter and rebuilt on each pass. `lazy-lock.json` belongs to the box
  and is kept. A pre-existing `~/.config/nvim` not managed by the sync is
  renamed to `.bak.<timestamp>`.
- `try` and `proj`, used by the `p` alias and the `Ctrl+F` widget, are
  downloaded into `~/.local/bin` from the URLs found in `install/bootstrap.sh`.
  Any tool added to the repo the same way is picked up automatically.
- Git aliases (`co`, `br`, `ci`, `st`, `s`, `pull.rebase`, ...) come from the
  `setup` function of `install/git.sh`, which only makes `git config --global`
  calls.
- tmux is reloaded if it is running.

It runs on the very first start, then only when you ask for it: `devbox sync`,
or `devbox update dotfiles`. There is no periodic sync.

Edit the config in the repo, not in the box. Copied files are overwritten on
every pass. For box-only tweaks, put them in `~/.config/dev-box/overrides/`, a
mirror of the home: `overrides/.config/tmux/tmux.conf` becomes
`~/.config/tmux/tmux.conf`. They are re-applied at the end of every sync, after
the steps that overwrite, nvim included.

To follow your own dotfiles, point `DOTARCHY_REPO`, `DOTARCHY_BRANCH` and
`DOTARCHY_SUBDIR` in `.env` at them.

Not replicated: the rest of `bootstrap.sh` (keyboard layout, shell choice) and
`install/nvim.sh`. Its tweaks (`relativenumber = false`, `gb` remapped to
`<C-^>`) only apply here if they live in `config/nvim`.

## Seeded files and `devbox seed`

A base config is shipped in the image and laid down in the home by
`dev-box-seed`, which runs at every start and on `devbox update seed`. A
reference copy of what was laid down is kept in `~/.config/dev-box/seed/<path>`,
which gives three cases per file:

- **missing**: the shipped file is copied and recorded as the reference;
- **untouched** (identical to the reference) and the shipped version changed:
  it is updated in place (`config updated: ~/x`);
- **modified locally** and the shipped version changed: nothing is overwritten,
  the box tells you the new version exists and how to take it with
  `dev-box-seed --force ~/x`, also written `devbox seed --force ~/x`. A bare
  `devbox seed` on a terminal opens a menu (apply, check, force one file or
  all); `devbox seed --apply` is the form with no menu, `devbox seed --check`
  looks without writing.

![dev-box-seed with two shipped files changed: the untouched one is updated in place, the locally modified one is left alone with the dev-box-seed --force command to take the new version](screenshots/dev-box-seed.png)

A box created before the reference existed simply adopts the shipped version as
its reference on the next start, without overwriting anything.

So a seeded file is yours to edit: your change is kept, and a new shipped
version is only reported.

| File | From |
| --- | --- |
| `~/.claude/settings.json` | `rootfs/etc/devbox/claude/settings.json` |
| `~/.claude/agents/{pi,omp}.md` | `rootfs/etc/devbox/claude/agents/` |
| `~/.pi/agent/extensions/llm-proxy.ts` | `rootfs/etc/devbox/llm-proxy.ts` |
| `~/.omp/agent/extensions/llm-proxy.ts` | same file |
| `~/.config/mise/config.toml` | `rootfs/etc/devbox/mise-config.toml` |
| `~/.config/yazi/keymap.toml` | `rootfs/etc/devbox/yazi/keymap.toml` |

- `settings.json`: theme, effort level, empty commit/PR attribution, and the
  `harness@c4software` plugin from its GitHub marketplace. There is no `model`
  key, so Claude Code picks its own default. Claude Code rewrites this file by
  itself, so it goes to "modified locally" almost immediately. That is
  expected. A new shipped version is reported, never forced.
- `pi.md` and `omp.md`: Claude Code sub-agents that delegate a task to the `pi`
  and `omp` CLIs. They only run when asked for explicitly.
- `llm-proxy.ts` registers the Albert (DINUM) provider in pi and omp. It reads
  `LLM_PROXY_URL` and `LLM_PROXY_API_KEY` from `.env`. If the endpoint is
  unreachable it registers nothing rather than blocking startup.
- `config.toml` is the mise config, the dev tools of the box (see
  [tools.md](tools.md#dev-tools-mise)). `mise use -g` and `devbox dev-env`
  write into it, and so does the first call of a coding agent, whose wrapper
  declares it there: from then on the file is "modified locally", and a new
  shipped version is reported rather than applied. Older images shipped a
  version that declared `claude`, `pi`, `codex` and `omp`; a box whose file was
  never touched loses those lines at the next start, and each agent it still
  uses declares itself again on its next call, at the version already
  installed.
- `keymap.toml` adds the `c t` chord to yazi, which sends the selected files
  over Taildrop (see [terminal.md](terminal.md#the-file-manager)). It only
  prepends bindings, the yazi defaults stay. It is the place for your own
  bindings too.

## Your own dev environments

A script in `~/.config/dev-box/dev-envs/<name>.sh` adds an environment to
`devbox dev-env` on your box, or replaces the image's one of the same name, and
survives rebuilds since it lives in the home; `--list` marks it. The format is
described at the top of `/usr/share/devbox/lib/dev-env.sh`, and copying one of
the image's scripts from `/usr/share/devbox/dev-envs/` is the quickest start.
See [dev-envs.md](dev-envs.md) for what the shipped ones do.

## Wrappers in `~/.local/bin` and `devbox mise-install`

`claude`, `pi`, `omp`, `opencode` and `codex` already have a wrapper in
`/usr/local/bin` that installs them through mise on the first call.
`devbox mise-install` writes the same kind of wrapper for anything else:

```bash
devbox mise-install               # menu: write, list or remove, gum asks the rest
devbox mise-install npm:@google/gemini-cli gemini
devbox mise-install crush
devbox mise-install --list        # the wrappers written this way
devbox mise-install --remove gemini
```

It takes `<package> [command [binary]]` and writes `~/.local/bin/<command>`.
The wrapper runs `mise use -g --quiet <package>` when mise cannot find the
command yet, then `mise x <package> -- <binary>`, with
`MISE_MINIMUM_RELEASE_AGE=0` so asking for a tool by name gets today's release. `~/.local/bin` comes before
`/usr/local/bin` on the `PATH`, so a wrapper written here takes over from the
one in the image when it carries the same name. The same goes for any script
you drop there yourself.

## Packages that survive a rebuild

`devbox pkg add <package>` installs a pacman package and puts it back at every
start, from `~/.config/dev-box/packages`. See
[tools.md](tools.md#persistent-packages).

## The default coding agent

`devbox agent set` picks the agent the box runs by default, kept in
`~/.config/dev-box/agent`. See [agents.md](agents.md).

## Reviewing it all: `devbox override`

`devbox override` lists what this box changes from the image defaults: where
each change lives, and an `undo:` line with the command that goes back to the
default. It is the first thing to read when a box behaves differently from
another one built from the same image. It is read only: nothing is written,
nothing goes over the network, and the `undo:` lines are printed, never run.

```bash
devbox override                                    # the list, by kind
devbox override --diff                             # every file override, as a unified diff
devbox override --diff ~/.config/mise/config.toml  # one file
```

What it reports:

- the seeded config that differs from the version in `/etc/devbox/`; a file
  equal to its reference copy in `~/.config/dev-box/seed/` is not your doing
  and is left out. For the mise config, the tools added, removed or pinned to
  another version;
- the files of `~/.config/dev-box/overrides/`, whether they replace a dotarchy
  file, and whether `devbox sync` has applied them yet;
- the dotfiles changed or deleted since the last `devbox sync`, which the next
  sync overwrites; the `undo:` line also gives the copy into `overrides/` that
  keeps the change;
- `~/.config/dev-box/dev-envs/`, the scripts in `~/.local/bin` that shadow a
  command of `/usr/local/bin` or `/usr/bin`, the default agent, the packages of
  `devbox pkg`;
- the `.env` settings the box can see from a shell (`TS_DISABLE`, `DEV_ENVS`,
  `LLM_PROXY_URL`, `PODMAN_ENABLE`, `DOTARCHY_*`, `USER_NAME`, `USER_SHELL`,
  `TS_HOSTNAME`, `PROJECTS_DIR`);
- what `compose.override.yaml` adds to the container: extra volumes,
  `mem_limit` and `cpus`, devices, capabilities, and the `security_opt` of the
  podman block.

Variables only the entrypoint sees (`UPDATE_CHECK_INTERVAL`,
`MISE_INSTALL_ON_START`, `TS_EXTRA_ARGS`, ...) are not listed: an SSH session
cannot read them.
