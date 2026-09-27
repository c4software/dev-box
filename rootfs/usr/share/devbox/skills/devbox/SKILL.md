---
name: devbox
description: >
  REQUIRED for the dev-box container itself, not a project inside it: the
  devbox command and dev-box-* binaries, /etc/devbox and ~/.config/dev-box,
  installing a language (dev-env), a pacman package that survives a rebuild,
  the global mise config, podman, databases, the GPU, dotfiles (dotarchy),
  updates, access (Tailscale, sshd, Taildrop), agent wrappers, a browser to
  screenshot or drive a page, the dev-box repo. Also when something in the box
  breaks: command not found, no network, disk full, cannot ssh, a change lost
  after a rebuild.
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
- [`browser.md`](browser.md) - rendering and driving a page in the box: agent-browser, headless Chromium, screenshots, Playwright and Puppeteer on the system Chromium
- [`diagnostic.md`](diagnostic.md) - something in the box is broken: facts first, then a diagnosis, then a fix the user agreed to

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

A change that must survive a rebuild goes in the repository, followed by a
rebuild of the container on the host. There is no other path. See `extending.md`.

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
4. **Is it an Arch package?** `devbox pkg add <packages>`: pacman installs it
   and the box puts it back after a rebuild. A package every box should have
   still belongs in the `Dockerfile`. See `extending.md`.
5. **Is it a CLI tool with no wrapper yet?** `devbox mise-install <package>
   [command]` writes one in `~/.local/bin`. Agents included.
6. **Is it about the coding agent itself?** `devbox agent`: `set`, `which`,
   `prompt`, and `usage` for what is left of the account limits.
7. **Is a home left over from an older image misbehaving?** `devbox migrate
   --pending`, then `devbox migrate`.
8. **Is it a file to move in or out of the box?** `devbox tailscale send` and
   `devbox tailscale receive`, over Taildrop.
9. **Is it a page to look at or click through?** `agent-browser` on the
   system Chromium, installed on demand with `devbox dev-env browser`; never
   `npx playwright install`. See `browser.md`.
10. **Is it a config file shipped by the image?** It is in the `SEEDS` table of
   `dev-box-seed`. Change it in the repository, not in `/etc/devbox/`.
11. **Is it a personal tweak to the dotfiles config?** Put it in
   `~/.config/dev-box/overrides/`, which mirrors the home.
12. **Is it a change to the dotfiles themselves?** They belong to the dotarchy
   repository, not to this box. `devbox sync` only copies them here.
13. **Is it an update?** Nothing is automatic except migrations. See
    `updates.md`.
14. **Is something in the box broken?** Follow `diagnostic.md`: start with
    `devbox diagnostic --report`, read only, and ask before fixing.
15. **Unsure?** `devbox status`, then `devbox commands`.

## Out of Scope

- The host. The Compose commands (`docker compose up -d`, `docker compose
  build`, `docker compose pull`) and `scripts/backup.sh` run on the machine
  hosting the container, not in here. The box can print the
  command to run, it cannot run it.
- The dotarchy dotfiles content. The box consumes that repository, it does not
  own it.

## Example Requests

- "Install Go" -> `devbox dev-env go`
- "Remove Go" -> `devbox dev-env --remove go`
- "Start a postgres" -> `devbox dbs postgres`; `devbox dbs --list` for what is
  running and what is on offer
- "Connect to the postgres" -> `psql -h 127.0.0.1 -U postgres` (psql and mariadb
  are in the image); mongosh, usql, mycli: `devbox dev-env db-clients`
- "Install nmap" or "capture traffic" -> `devbox dev-env network`, then
  `sudo nmap -sS` or `sudo tcpdump -i any`; dig, nc, whois are already there
- "Install ansible" -> `devbox dev-env ansible`
- "Use the GPU" or "hardware video encoding" -> `ls /dev/dri` first: empty,
  the host has to add `/dev/dri` to the devices of compose.override.yaml and
  restart the container; there, `devbox gpu install`, then `devbox gpu`
  (access, VA-API codecs, Vulkan) and `devbox gpu test`
- "What is available to install?" -> `devbox dev-env --list`
- "What does the ruby environment install?" -> `devbox dev-env --info ruby`
- "Add an environment for a tool of mine" -> a script in
  `~/.config/dev-box/dev-envs/<name>.sh`, format at the top of
  `/usr/share/devbox/lib/dev-env.sh`
- "How does this box work?" -> `devbox tour`, or `devbox tour --text` to read it all
- "Have Go and Node in every box" -> `DEV_ENVS="node go"` in `.env` on the host,
  installed at start when missing (`devbox status` shows where it stands)
- "Put the box in French" -> `LANG=fr_FR.UTF-8` in `.env` on the host, then
  restart the container: only the `devbox` menu and the login tips are
  translated, everything else stays in English
- "Update the box" -> `devbox update`, after saying what it will do
- "Is there anything to update?" -> `devbox check`, then `devbox status`
- "Add ripgrep" -> already in the image
- "Install ripgrep-all" -> `devbox pkg add ripgrep-all`, which also puts it back
  after a rebuild; a package every box should have goes in the `Dockerfile`
- "Add a gemini wrapper" -> `devbox mise-install npm:@google/gemini-cli gemini`
- "Fix my old mise config" -> `devbox migrate --pending`, then `devbox migrate`
- "Run my agent on this repo" -> `devbox agent prompt "..."`; `devbox agent set`
  to change which one
- "How much of my Claude quota is left?" -> `devbox agent usage claude`
- "Send this file to my laptop" -> `devbox tailscale send laptop <file>`
- "Check the page renders" -> `devbox dev-env browser` once, then
  `agent-browser open <url>`, `agent-browser snapshot`,
  `agent-browser screenshot /tmp/page.png`; see `browser.md`
- "My tmux config change disappeared" -> it was overwritten by `devbox sync`;
  move it to `~/.config/dev-box/overrides/.config/tmux/tmux.conf`
- "docker says it cannot reach the API" -> rootless podman is off, see
  `architecture.md`; enabling it is a host-side change
- "Add a new devbox command" -> a `dev-box-<name>` script in the repository with
  `# devbox:` headers, see `extending.md`
- "Why is my edit to /usr/local/bin gone?" -> it was in the image; see
  `extending.md`
- "Postgres does not start" / "the box is broken" -> `diagnostic.md`, starting
  with `devbox diagnostic --report`; nothing is changed without asking
