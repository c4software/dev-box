---
name: devbox
description: >
  REQUIRED whenever work touches the dev-box container itself rather than a
  project inside it. Use for the `devbox` command and any `dev-box-*` binary
  (seed, update, check, status, dev-env, dbs, podman), for `/etc/devbox/`,
  `/usr/share/devbox/`, `~/.config/dev-box/`, the global mise config
  `~/.config/mise/config.toml`, installing a language or dev environment in the
  box, rootless podman inside the box, dotfiles sync (dotarchy-sync), updating
  the box, the login message about pending updates, Tailscale or sshd access to
  the box, and any change to the dev-box repository (Dockerfile, rootfs/,
  compose.yaml, justfile, README). Triggers: devbox, dev-box, dev-box-update,
  dev-box-seed, dev-box-dev-env, mise config, box update, rebuild the image,
  "install go/python/ruby in the box", "why is my change gone after a rebuild".
---

# dev-box Skill

This box is a Docker container running Arch Linux, built from the
[c4software/dev-box](https://github.com/c4software/dev-box) repository. The
image is disposable; the home directory is not. Almost every mistake made in
here comes from editing something that lives in the image.

## When This Skill MUST Be Used

- Any `devbox` or `dev-box-*` command.
- Reading or changing `/etc/devbox/`, `/usr/local/bin/`, `/usr/share/devbox/`.
- Reading or changing `~/.config/dev-box/` or `~/.config/mise/config.toml`.
- Installing a language, runtime or toolchain in the box.
- Podman or `docker` inside the box.
- Updating the box, or explaining why an update did not happen.
- Any edit to a clone of the dev-box repository.

**Before editing a file under `/etc/devbox/`, `/usr/local/bin/` or
`/usr/share/devbox/`, stop and read `extending.md` instead.**

## Topic Guides

Read the matching guide before starting:

- [`architecture.md`](architecture.md) - what is in the image, what is in the home, how a start goes
- [`commands.md`](commands.md) - `devbox` and every command it dispatches to
- [`extending.md`](extending.md) - how to change the box for good, through the repository
- [`updates.md`](updates.md) - what updates, when, and on whose command

## Critical Safety Rules

**Never edit anything in `/usr/local/bin/`, `/etc/devbox/` or
`/usr/share/devbox/`.** Reading them is safe and encouraged. They come from the
image, so any change there is lost the next time the image is rebuilt, and it
is lost silently: the box keeps working until the rebuild, then the change
simply is not there any more.

```
/usr/local/bin/      READ ONLY   the devbox commands and the tool wrappers
/etc/devbox/         READ ONLY   the config shipped by the image
/usr/share/devbox/   READ ONLY   this skill and its guides
```

Write here instead:

| Place | For |
|---|---|
| `~/.config/dev-box/overrides/` | box-only tweaks to the dotfiles config, mirrored on the home |
| `~/.config/mise/config.toml` | dev tools (through `mise use -g`, or `devbox dev-env`) |
| `~/projets/dev-box` (a clone) | everything that must survive a rebuild |
| `~/` generally | your own files |

A change that must survive a rebuild goes in the repository, followed by
`just rebuild` on the host. There is no other path. See `extending.md`.

`sudo` works without a password in the box, which makes it easy to write in the
wrong place. Passwordless is not permission.

## Command Discovery

`devbox` dispatches to the `dev-box-*` binaries. It builds its list by reading
`# devbox:` comment headers in `/usr/local/bin/`, so the list is always the
truth about this image.

```bash
devbox --help          # usage and the table of commands
devbox commands        # bare list, one name per line
devbox status          # what the box is doing right now
devbox <cmd> --help    # summary, usage, and the command's own help

cat $(which dev-box-update)   # read the source, it is short bash
```

Never guess a command name. Run `devbox commands`.

## Decision Framework

1. **Is it a box command?** Use `devbox <cmd>`. See `commands.md`.
2. **Is it a dev tool or a language?** `devbox dev-env <env>`, or
   `mise use -g <tool>`. Never `sudo pacman -S`, which is lost on rebuild.
3. **Is it a database to run?** `devbox dbs <db>`: a podman container, data in a
   named volume. Never install a database server in the box itself.
4. **Is it a system package?** It belongs in the `Dockerfile`. See
   `extending.md`.
5. **Is it a config file shipped by the image?** It is in the `SEEDS` table of
   `dev-box-seed`. Change it in the repository, not in `/etc/devbox/`.
6. **Is it a personal tweak to the dotfiles config?** Put it in
   `~/.config/dev-box/overrides/`, which mirrors the home.
7. **Is it a change to the dotfiles themselves?** They belong to the dotarchy
   repository, not to this box. `devbox sync` only copies them here.
8. **Is it an update?** Nothing is automatic. See `updates.md`.
9. **Unsure?** `devbox status`, then `devbox commands`.

## Out of Scope

- The host. `just up`, `just rebuild`, `just backup` and the Compose commands
  run on the machine hosting the container, not in here. The box can print the
  command to run, it cannot run it.
- The dotarchy dotfiles content. The box consumes that repository, it does not
  own it.

## Example Requests

- "Install Go" -> `devbox dev-env go`
- "Start a postgres" -> `devbox dbs postgres`; `devbox dbs --list` for what is
  running and what is on offer
- "What is available to install?" -> `devbox dev-env --list`
- "Update the box" -> `devbox update`, after saying what it will do
- "Is there anything to update?" -> `devbox check`, then `devbox status`
- "Add ripgrep" -> already in the image; anything genuinely missing goes in the
  `Dockerfile` (see `extending.md`), never `sudo pacman -S`
- "My tmux config change disappeared" -> it was overwritten by `devbox sync`;
  move it to `~/.config/dev-box/overrides/.config/tmux/tmux.conf`
- "docker says it cannot reach the API" -> rootless podman is off, see
  `architecture.md`; enabling it is a host-side change
- "Add a new devbox command" -> a `dev-box-<name>` script in the repository with
  `# devbox:` headers, see `extending.md`
- "Why is my edit to /usr/local/bin gone?" -> it was in the image; see
  `extending.md`
