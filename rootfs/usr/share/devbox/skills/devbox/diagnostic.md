# Diagnosing a broken box

The procedure to follow when the box itself misbehaves: a login that fails, a
tool that is not found, a dev environment that will not install, a database
that will not start, `docker` that refuses to run, a full disk, no network, an
update that never lands. `devbox diagnostic` starts the default coding agent
on this guide; a user can also just describe the problem.

The order never changes: **facts first, then a diagnosis, then a fix the user
agreed to.** Most of what looks broken in a box is one of four things: a
feature that is off on purpose (podman, sshd), a background install still
running or failed at start, a change made in the image and lost on rebuild, or
something only the host can fix.

## 1. Gather the facts, read only

Start with the report. It runs only read-only commands, each bounded by a
timeout, and prints no secret:

```bash
devbox diagnostic --report
```

It covers the image and access (`devbox status`), the default agent and
whether it has credentials, disk space and memory, ownership of the home,
the shipped config (`devbox seed --check`), pending migrations, mise, the
`DEV_ENVS` state and the tail of its log, the persistent packages, podman and
the `devbox dbs` containers, DNS and HTTPS reachability, and the tails of the
start logs. Read it whole before forming an opinion.

Then dig into the area the user described, still read only:

| Area | Read-only commands |
|---|---|
| overall | `devbox status`, `devbox --help`, `cat /etc/devbox/release` |
| shipped config | `devbox seed --check` |
| migrations | `devbox migrate --list`, `devbox migrate --pending`, `cat ~/.config/dev-box/migrations` |
| mise, a tool not found | `mise doctor`, `mise ls --current`, `mise which <cmd>`, `cat ~/.config/mise/config.toml`, `echo $PATH`, `type -a <cmd>` |
| mise install at first start | `tail -n 50 ~/.cache/dev-box-install.log` |
| dev environments | `devbox dev-env --list`, `devbox dev-env --info <env>`, `cat ~/.cache/dev-box/dev-envs`, `tail -n 80 ~/.cache/dev-box/dev-envs.log` |
| persistent packages | `devbox pkg list`, `tail -n 50 /tmp/dev-box-pkg.log` |
| podman, docker | `cat /etc/devbox/podman.state`, `ls -l /run/user/$(id -u)/podman/podman.sock`, `tail -n 50 ~/.cache/dev-box-podman.log`, `PODMAN_FORCE=1 podman info` |
| databases | `devbox dbs --list`, `podman ps -a --filter name=devbox-`, `podman logs --tail 50 devbox-<name>`, `podman volume ls` |
| disk | `df -h / ~ ~/projets /tmp`, `du -xsh ~/.local/share/mise ~/.cache ~/.local/share/containers 2>/dev/null`, `podman system df` |
| network, DNS | `cat /etc/resolv.conf`, `getent hosts github.com`, `curl -sSI --max-time 5 https://github.com` |
| Tailscale | `tailscale status`, `tailscale netcheck`, `devbox serve status` |
| sshd (`TS_DISABLE=true`) | `pgrep -a sshd`, `ls -ld ~ ~/.ssh`, `ls -l ~/.ssh/authorized_keys` |
| the home | `ls -ld ~ ~/.config ~/projets`, `find ~ -maxdepth 2 ! -user "$(id -u)"` |
| updates | `cat ~/.cache/dev-box/updates`, `devbox check --image`, `devbox changelog --upcoming` |
| the agent | `devbox agent which`, `devbox agent usage` |
| the dotfiles | `git -C ~/.local/share/dotarchy status`, `ls ~/.config/dev-box/overrides` |

Rules for this step:

- Never print `/etc/devbox/env`, `~/.claude/.credentials.json`,
  `~/.codex/auth.json`, `~/.pi/agent/auth.json`, or any key or token. Test
  that a file exists, never show its content.
- `devbox check` and `devbox changelog` reach the network and write a cache
  file: harmless, but say so before running them.
- The start log of the container (`docker logs dev-box`) is on the host. When
  the box's own traces do not explain a start failure, ask the user to run
  `docker logs dev-box` on the host and paste the end.

## 2. Diagnose

Say what is wrong, in one or two sentences, and what in the facts shows it.
When the facts do not settle it, say which command would, and run it.

Known causes, by symptom:

- **`docker` or `podman` says podman is not active**: rootless podman is off by
  design. Enabling it is a host-side change (the podman block of
  `compose.override.yaml`, `PODMAN_ENABLE=true` in `.env`, restart the container). With
  `podman.state` at `enabled` and no socket, the service failed at start: read
  `~/.cache/dev-box-podman.log`, usually `/dev/fuse` or `security_opt`
  missing from the override.
- **`devbox dbs <db>` fails**: podman first (above). Then the port: `mysql`
  and `mariadb` both want 3306, only one runs at a time. `mssql` has no arm64
  image. A database does not restart on its own after the box restarts:
  `devbox dbs --start <db>`. A container that exits at once: its
  `podman logs`. A full disk shows up here too.
- **A command is not found** (`node`, `go`, `claude`, ...): is it declared in
  `~/.config/mise/config.toml`? Is it installed (`mise ls --current`)? Is the
  first-start install still running or failed
  (`~/.cache/dev-box-install.log`)? A command installed with `sudo pacman -S`
  is gone after a rebuild: it belonged in `devbox pkg add` or `devbox dev-env`.
  A shell that is not a login shell may miss mise's activation: `zsh -l`.
  A missing shim (`mise doctor`, and the report) is fixed by `mise reshim`,
  which only rewrites `~/.local/share/mise/shims`.
- **`devbox dev-env` failed**: the log names the step. Network, a tool name
  the mise registry no longer knows, an environment that `--unsupported`
  lists on this architecture (x86_64 only ones on arm64), or a disk full of
  toolchains.
- **An old home misbehaves after an update**: `devbox migrate --pending`, and
  `devbox seed --check` for a shipped file the user changed, which the seed
  never overwrites.
- **A change to `/usr/local/bin`, `/etc/devbox` or `/usr/share/devbox` is
  gone**: it lived in the image. See `extending.md`.
- **A dotfiles tweak keeps coming back to the old value**: `devbox sync`
  overwrote it. It belongs in `~/.config/dev-box/overrides/`.
- **SSH or Tailscale login fails**: with Tailscale, `tailscale status` says
  whether the node is logged in and online; a node that needs a login again
  is fixed from the host (`docker logs dev-box` shows the login URL, or a new
  `TS_AUTHKEY` in `.env` and restart the container). With `TS_DISABLE=true`, sshd only
  accepts the keys of `SSH_AUTHORIZED_KEYS`, and refuses a home or `~/.ssh`
  writable by group or others (StrictModes). Both are host-side settings.
- **Permission denied in the home**: files owned by root or another UID, left
  by a `sudo` command or a container run with the wrong user. The box's user
  is always 1000:1000.
- **No network or DNS**: compare `getent hosts` with `curl`. DNS failing
  alone points at `/etc/resolv.conf`, which Docker writes on the host side;
  everything failing points at the host or its network.
- **Disk full**: the usual weights are `~/.local/share/mise` (old toolchain
  versions, `mise prune` lists them with `--dry-run`),
  `~/.local/share/containers` (podman images and volumes), `~/.cache`.
- **The agent will not start or is not logged in**: `devbox agent which`,
  then run the agent once by hand and log in (`/login` in claude and codex).

## 3. Propose, then ask

Propose the fix as the exact commands, and say for each one what it changes
and whether it can be undone. Then **ask before running anything that
changes state**, and wait for the answer. That includes:

- deleting anything: files, caches, `mise prune`, `podman system prune`,
  `devbox dbs --remove --purge`, `podman volume rm`;
- `devbox seed --force`, which overwrites a file the user changed;
- `devbox migrate --mark-done`, which skips a repair for good;
- `devbox update`, `devbox sync`, `devbox dev-env --remove`, `devbox pkg drop`;
- `sudo chown` or `chmod` on the home;
- anything with `sudo`.

Read-only commands need no permission. Restarting a stopped database with
`devbox dbs --start <db>` or re-running a failed `devbox dev-env <env>` is
safe to propose and quick to accept, but still ask.

When the fix is on the host (`.env`, `compose.override.yaml`, restarting
or rebuilding the container, `docker logs dev-box`), say so plainly and print the commands for the
user to run there: the box cannot run them.

## 4. Check, and hand over

After a fix, run the command that showed the problem again and show that it
is gone. When nothing is found, say what was checked. When the user needs
help from someone else (a teacher, a colleague), suggest
`devbox diagnostic --report > ~/diagnostic.txt` and add what was tried; the
report contains no secret, but read it before sending it.
