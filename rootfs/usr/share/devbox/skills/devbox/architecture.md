# Architecture of the box

Two layers, and the line between them is the only thing you really have to
remember.

## The image (rebuilt, never edited in place)

Everything below comes from the `rootfs/` directory of the dev-box repository
and is copied into the image at build time. It is read only in practice: a
change made here survives until the next `just rebuild` on the host, then
vanishes without warning.

| Path | Holds |
|---|---|
| `/usr/local/bin/` | `devbox`, the `dev-box-*` commands, `dotarchy-sync`, the tool wrappers (`claude`, `pi`, `omp`, `codex`, `opencode`), the `wl-copy`/`wl-paste`/`xdg-open`/`notify-send` shims |
| `/etc/devbox/` | the config shipped to the home (`mise-config.toml`, the Claude agents, `llm-proxy.ts`, the yazi keymap), plus `zshenv`, `zshrc`, `sshd_config`, `updates-motd.sh` |
| `/usr/share/devbox/skills/` | this skill and its guides |
| `/usr/share/devbox/migrations/` | the one-off repairs run at start, once each |
| `/etc/devbox/release` | `DEVBOX_COMMIT`, `DEVBOX_REPO`, `DEVBOX_BRANCH`, `DEVBOX_VERSION` (the tag), `DEVBOX_SOURCE` (`release` or `local`), burned in at build time; read through `/usr/share/devbox/lib/release.sh` |
| `/etc/containers/` | the rootless podman setup |

System packages come from pacman, in the `Dockerfile`. `sudo pacman -S` inside
the box works and is lost on the next rebuild.

## The home (persistent, yours)

`/home/<user>` is a bind mount from the host (`./data/home`). It survives every
rebuild. `~/projets` is a second, separate bind mount, so the projects can be
backed up or moved on their own.

| Path | Holds |
|---|---|
| `~/.config/mise/config.toml` | the dev tools, the only declaration that matters |
| `~/.local/share/mise/` | the toolchains themselves |
| `~/.config/dev-box/seed/` | a reference copy of the config the image laid down |
| `~/.config/dev-box/overrides/` | your box-only tweaks, a mirror of the home |
| `~/.config/dev-box/migrations` | the migrations already played, one name per line |
| `~/.config/dev-box/packages` | the pacman packages `devbox pkg` puts back at every start |
| `~/.config/dev-box/agent` | the default coding agent |
| `~/.config/dev-box/dev-envs/` | your own `devbox dev-env` environments, one script each (optional) |
| `~/.config/dev-box/tour-pending` | the first login proposes the guided tour, then removes it |
| `~/.local/share/dotarchy/` | the dotfiles clone |
| `~/.cache/dev-box/updates` | the pending-updates flag |
| `~/.cache/dev-box/dev-envs` | the `DEV_ENVS` flag: installing, or failed; gone when all is there |
| `~/projets/` | your repositories, on their own volume |

The user is `dev` by default, always UID/GID 1000:1000, so files have the same
owner on the host side of the bind mounts. `sudo` needs no password.

## What a start does

`entrypoint.sh` runs as root, in this order:

1. creates the user and the home if they are missing, fixes ownership;
2. `dev-box-seed` lays down the shipped config (see below);
3. links this skill into `~/.claude/skills/`, `~/.pi/agent/skills/` and
   `~/.omp/agent/skills/`;
4. runs `dev-box-migrate` as your user, the only automatic step in the box; a
   first start marks every migration as played instead of running them, and
   flags the guided tour for the first login (`devbox tour`);
5. reinstalls the missing packages of `~/.config/dev-box/packages`, in the
   background;
6. starts `tailscaled` and `tailscale up`, or OpenSSH when `TS_DISABLE=true`;
7. starts the rootless podman socket when `PODMAN_ENABLE=true`;
8. on the very first start only, runs `dotarchy-sync` and installs the mise
   tools in the background (`~/.cache/dev-box-install.log`);
9. installs the dev environments of `DEV_ENVS` that are missing, in the
   background, through `dev-box-dev-env --if-missing`
   (`~/.cache/dev-box/dev-envs.log`); already installed ones are skipped;
10. then only checks for updates, every `UPDATE_CHECK_INTERVAL` seconds.

Nothing else runs on its own. No package is upgraded behind your back, and the
migrations of step 4 only repair what an older image left behind.

## The seed, and its three cases

`dev-box-seed` copies the config shipped by the image into the home and keeps a
reference copy of what it laid down in `~/.config/dev-box/seed/<path>`. That
reference is what lets it tell "never touched" from "you changed it":

- **missing**: the file is copied, and recorded as the reference;
- **identical to the reference**, and the shipped version changed: it is
  updated in place, silently and safely;
- **different from the reference**: nothing is overwritten. The box says a new
  version exists and prints `dev-box-seed --force <path>` to take it.

The table of what is seeded is the `SEEDS` array at the top of
`dev-box-seed`. Read it with `cat $(which dev-box-seed)`.

## Overrides

`~/.config/dev-box/overrides/` mirrors the home. `overrides/.config/tmux/tmux.conf`
becomes `~/.config/tmux/tmux.conf`. `dotarchy-sync` re-applies the overrides at
the very end of every pass, after the steps that overwrite, so they always win.
This is the right place for a tweak that belongs to this box and not to the
dotfiles repository.

## Access

Either Tailscale or a plain sshd, never both:

- default: `tailscaled` runs in the container and Tailscale SSH opens the
  shell. Nothing is published on the host.
- `TS_DISABLE=true`: the box runs its own OpenSSH on a published port, public
  key only, keys taken from `SSH_AUTHORIZED_KEYS`.

A login lands in zsh inside a tmux session named after the box. `NO_TMUX=1`
gives a plain shell.

## Podman, opt-in

`docker` and `podman` on `PATH` are symlinks to `dev-box-podman`, a wrapper. If
rootless podman is not enabled, the wrapper says so and lists the three steps to
enable it, instead of letting podman fail on an obscure error. Those steps are
host-side: a Compose override block, `PODMAN_ENABLE=true`, then `just up`.
Enabling it loosens the box's own isolation, which is why it is off by default.
`PODMAN_FORCE=1`, or `/usr/bin/podman`, bypasses the wrapper.
