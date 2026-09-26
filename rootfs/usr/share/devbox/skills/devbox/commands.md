# Commands

## devbox, the front door

`devbox` is the single entry point. It does not hold a hardcoded list: it scans
the executables of `/usr/local/bin/` and reads their `# devbox:` comment
headers. What `devbox --help` prints is therefore always what this image
actually ships.

```bash
devbox                 # menu of commands (gum), then runs the one you pick
devbox <cmd> [args]    # run a command
devbox <cmd> --help    # summary, usage, then the command's own help
devbox --help          # usage and the table of commands
devbox commands        # bare list, one name per line, for completions
```

An unknown name exits non-zero and prints the list. The menu needs a terminal;
without one it says so and prints the list rather than hanging.

Every command with subcommands opens a menu of its own when it runs with a
terminal and no argument, then asks with gum for what it needs (a package, a
port, a machine, a file). Without a terminal nothing asks: `update` updates
everything, `migrate` runs what is pending, `seed` applies, and the others
print their usage. Scripts and the entrypoint always give arguments; the
explicit forms are `update all`, `migrate --run` and `seed --apply`.

Every command is still on `PATH` under its own name, and that is the name to
use in scripts and in the `justfile`: `devbox update` and `dev-box-update` are
the same binary.

## The commands

| `devbox` | Binary | Does |
|---|---|---|
| `status` | `dev-box-status` | image commit and repo, Tailscale or sshd, podman, mise tools, the `DEV_ENVS` environments, pending updates. Read only. |
| `check` | `dev-box-check-updates` | looks for what could be updated, writes the flag and prints it. `--image` only says whether the image is the latest, `--quiet` writes the flag and prints nothing (the entrypoint, `devbox update`). Installs nothing. |
| `update` | `dev-box-update` | `[dotfiles\|tools\|seed\|all]`, default `all`. The only command that installs. |
| `seed` | `dev-box-seed` | lays down the config shipped by the image. `--apply` with no menu, `--check` to look, `--force [path]` to take a new version. |
| `override` | `dev-box-override` | lists where this box departs from what the image ships, and the command that goes back to the default for each. `--diff [path]` prints the changes in the files. Read only. |
| `sync` | `dotarchy-sync` | clones or updates the dotfiles repo and applies the config. Never runs its install scripts. |
| `dev-env` | `dev-box-dev-env` | installs or removes a dev environment with mise. `--list`, `--info <env>`, names as arguments (`--remove` to remove, `--if-missing` to skip what is there), or a menu. |
| `tui` | `dev-box-tui` | installs or removes terminal apps from a catalogue (btop, lazydocker, atac, rainfrog, ...), through `devbox pkg`. `--list`, names as arguments (`--remove` to remove), or a menu. |
| `dbs` | `dev-box-dbs` | starts a development database in a podman container. `--list`, `--start`, `--stop`, `--remove [--purge]`, or names, or a menu. |
| `diagnostic` | `dev-box-diagnostic` | starts the default agent on the diagnostic guide (`diagnostic.md`) with the problem given as arguments. `--report` prints the facts with no agent, `--prompt` the instruction, `--dry-run` which agent would run. |
| `agent` | `dev-box-agent` | the default coding agent. `set`, `which`, `prompt <text>`, `usage [claude\|codex\|proxy]`, or bare for a menu (run, pick, usage). |
| `motd` | `dev-box-motd` | the login line: one command drawn at random, pending updates, `DEV_ENVS` still installing or failed. |
| `changelog` | `dev-box-changelog` | the release notes of the repo (GitHub releases), newest first. The 3 latest up to this image, `-n N`, `--all`, `--upcoming` for the releases after it; `--new` and `--mark-seen` are for the login and the entrypoint. |
| `tour` | `dev-box-tour` | a guided tour of the box in a dozen steps, each with the command to try. `--text` prints it at once, `--offer` is what the first login runs. |
| `migrate` | `dev-box-migrate` | runs the migrations shipped by the image, once each. `--run` with no menu, `--pending`, `--list`, `--mark-done <name>`. |
| `mise-install` | `dev-box-mise-install` | writes a mise-backed wrapper into `~/.local/bin`. `--list`, `--remove <cmd>`. |
| `pkg` | `dev-box-pkg` | pacman packages that survive a rebuild. `add`, `drop`, `list`, `install`, `restore`. |
| `serve` | `dev-box-serve` | publishes a local port to the tailnet with `tailscale serve`. `<port>`, `<listen>:<port>`, `--on <port>`, `--tcp`, `status`, `off [port\|all]`. |
| `tailscale` | `dev-box-tailscale` | Taildrop and tailnet status. `send [machine] <file...>`, `receive [--once] [dir]`, `status`. |

`dev-box-podman` carries `# devbox:hidden=true`: it is the wrapper behind the
`docker` and `podman` symlinks, not something a user calls. It stays routable,
it just does not clutter the menu.

## Reading a command

They are short bash scripts. Reading one is faster than guessing:

```bash
cat $(which dev-box-update)
cat $(which dev-box-seed)      # the SEEDS table is at the top
ls /usr/share/devbox/dev-envs/   # one script per dev-env environment
```

## dev-env

`devbox dev-env` installs or removes development environments with mise and
nothing else: no pacman, no `curl | sh`. Everything it installs is declared in
`~/.config/mise/config.toml`, so it survives a rebuild and is upgraded by
`devbox update tools`. Two exceptions, php and browser, are covered below.

```bash
devbox dev-env --list             # what is on offer, installed ones marked
devbox dev-env --info ruby        # what it installs, what a removal leaves
devbox dev-env node go            # install these two
devbox dev-env --remove node go   # remove these two
devbox dev-env --if-missing go    # install go only when it is not there yet
devbox dev-env --installed        # the installed names, one per line
devbox dev-env --unsupported      # the names this machine cannot take (x86_64 only ones on arm64)
devbox dev-env                    # menu: install or remove, then multiple selection
```

`DEV_ENVS="node go"` in `.env` on the host makes every start run
`dev-box-dev-env --if-missing node go` in the background, after the mise
tools: a fresh home gets its environments without a command, a rebuilt box
finds them again. An unknown name refuses the whole list. The output is in
`~/.cache/dev-box/dev-envs.log`, and the flag `~/.cache/dev-box/dev-envs`
carries one line, shown at login and by `devbox status`, while it runs or when
it failed. `DEV_ENVS` never removes anything, and an environment it lists
cannot be removed: `--remove` refuses it and the menu leaves it out, because
the next start would install it again. Take it out of `.env` on the host,
`just up`, then remove it.

Re-running on an environment already installed, or already removed, is
harmless. A removal (`mise unuse -g`) only takes out what the environment
brought: `laravel` keeps php and node, `phoenix` keeps elixir, `scala` keeps
java. Project data (`~/go`, `~/.cargo`, `~/.mix`, `~/.config/composer`, ...)
is never deleted.

PHP is baked into the image (pacman: php, composer, php-sqlite, php-gd,
php-sodium, xdebug, extensions enabled at build); `dev-env php` only checks it,
`laravel` and `symfony` add their installer on top. `android` is the
platform-tools only (adb, fastboot) through mise's http backend, x86_64 only,
refreshed by running the command again. `android-sdk` is the full SDK to build
apps (cmdline-tools pinned in mise, platform-tools, newest platform and
build-tools through sdkmanager, JDK 21 when no java is declared), and
`flutter` sits on it, Android and web targets; both x86_64 only, no emulator.
`browser` is a headless Chromium plus
`noto-fonts`, installed through `devbox pkg add` (pacman, reinstalled at start
after a rebuild) because the mise registry has no browser that runs on Arch
without those packages; see `browser.md` for how an agent uses it. OCaml is
absent: upstream it needs opam, which would be lost on the next rebuild.

Each environment is one script: `/usr/share/devbox/dev-envs/<name>.sh` for
the image's, `~/.config/dev-box/dev-envs/<name>.sh` for the box's own, which
wins over the image's of the same name and survives rebuilds. The format
(`details`, `install`, `uninstall`, optional `is_installed` and `is_supported`) is at the top of
`/usr/share/devbox/lib/dev-env.sh`; copying an image script is the quickest
start. `--list` marks the box's own scripts.

## tui

A catalogue of terminal apps, none installed until asked for: btop, htop,
ncdu, lazydocker, k9s, dive, atac, rainfrog, pgcli, jless, visidata, tealdeer,
glow, fastfetch, hyperfine, gping, trippy, termshark. Each name is the pacman
package, present on Arch Linux and Arch Linux ARM. The install goes through
`devbox pkg add`, so the app is written to `~/.config/dev-box/packages` and
reinstalled at start after a rebuild; `--remove` goes through `devbox pkg drop`.

```
devbox tui --list
devbox tui btop atac
devbox tui --remove btop
devbox tui                  # menu
```

When the user wants a terminal app that is not in the catalogue, use
`devbox pkg add <package>` (same persistence) rather than a bare pacman.
lazydocker needs podman (`PODMAN_ENABLE=true` on the host).

## dbs

`devbox dbs` runs development databases in rootless podman containers inside the
box, with the same images and development options as Omarchy's
`omarchy-install-docker-dbs` on the host.

```bash
devbox dbs                          # menu: start, stop, start again, remove, purge
devbox dbs --list                   # image, port and state of each database
devbox dbs postgres redis           # start these two
devbox dbs --stop redis             # stop, nothing is deleted
devbox dbs --start redis            # start an existing container again
devbox dbs --remove redis           # drop the container, keep the data
devbox dbs --remove --purge redis   # drop the data too, asks for confirmation
```

Names: `mysql` (3306), `postgres` (5432), `mariadb` (3306), `redis` (6379),
`mongodb` (27017), `mssql` (1433). Credentials are the development ones: empty
root password for mysql and mariadb, `trust` for postgres, `admin`/`admin123`
for mongodb, `sa`/`@dmin123` for mssql.

It needs rootless podman enabled (`PODMAN_ENABLE=true` plus the podman block in
`compose.override.yaml`, a host-side change). Without it, the command prints the
three steps and exits 1 without starting anything.

Containers are named `devbox-<name>` and their data lives in a podman volume
called `devbox-<name>`, so the data survives `--remove`. Re-running
`devbox dbs <name>` on an existing container starts it instead of recreating it.
Ports are published on `127.0.0.1`, reachable from inside the box only; from
outside, tunnel with `ssh -L 5432:127.0.0.1:5432 dev@dev-box`. `mysql` and
`mariadb` share port 3306, so only one of them runs at a time, and `mssql` has no
arm64 image. Nothing restarts on its own after a restart of the box.

## agent

`devbox agent` keeps one default coding agent for the box, in
`~/.config/dev-box/agent`, and runs it in the current directory.

```bash
devbox agent                    # menu: run the default, pick one, usage
devbox agent set [name]         # change it, gum menu when no name is given
devbox agent which              # print it
devbox agent prompt <text...>   # run it with an instruction
devbox agent usage [claude|codex|proxy]   # no name: the three of them
```

The choices are what the image ships (`claude`, `pi`, `omp`, `opencode`,
`codex`) plus every wrapper written by `devbox mise-install`. Nothing is
installed by `set`: the wrapper installs its tool on the first call.

`usage` is read only and prints one line per limit window: a twenty cell bar,
the percentage used, and a countdown to the reset in the box's timezone
(`resets in 2 h 13 min (16:45)`). The colors only appear on a terminal, so the
output stays greppable. Claude Code goes through the OAuth token in
`~/.claude/.credentials.json` and Anthropic's usage endpoint; the token travels
in that request's Authorization header and nowhere else, and no figure is
written to disk. Codex goes through `codex app-server` on stdin.
Without credentials each one says which command to run to log in.

Under the limits comes a `Tokens` block, the same one for the three accounts:
one line per model with its share of the last seven days as a twenty cell bar,
the share, the tokens, the requests and a sparkline of the seven days, today on
the right, then the input and output totals and what today weighs. Past the
eighth model the rest is folded into one `others` line. Those counts are read
from the local transcripts, `~/.claude/projects` for Claude Code and
`~/.codex/sessions` for Codex, so they still work when the account is not
logged in. `usage proxy` (alias `llmproxy`) prints the same block for the LLM
proxy, from its usage route on `LLM_PROXY_URL`, except that the percentage next
to the share bar is the cache hit rate of each model, the part of its input
served from the cache, under a header line naming the columns. Cached tokens are the
part of the input served from a cache and are never counted twice.

## diagnostic

`devbox diagnostic` hands a broken box to the default coding agent. The agent
reads `diagnostic.md`, gathers facts with read-only commands, says what is
wrong, and asks before changing anything.

```bash
devbox diagnostic "postgres does not start"   # the agent, on that problem
devbox diagnostic                             # the agent, looking for anything wrong
devbox diagnostic --report > ~/diagnostic.txt # the facts, no agent, to share
devbox diagnostic --prompt "..."              # the instruction, to paste elsewhere
devbox diagnostic --dry-run "..."             # which agent, which command line
```

The launch goes through `devbox agent prompt`, so the agent is the one of
`devbox agent set`. With none set, a terminal gets the menu to pick one; a
script gets the command to run. When the agent is `claude` or `codex` and no
credentials are found (the file, an API key variable, or a provider in its
settings), it stops and says how to log in; `--force` starts it anyway. The
other agents cannot be told from outside and are started as they are.

`--report` needs no agent: `devbox status`, system and disk, ownership of the
home, the agent and whether it has credentials, `devbox seed --check`,
`devbox migrate --pending`, `mise doctor` and missing tools, the `DEV_ENVS`
flag and log, the persistent packages, podman and the `devbox-*` containers,
DNS, HTTPS and the LLM proxy, then a list of findings. Every command is read
only and bounded by a timeout, and it prints no secret: the presence of a
credential file is tested, never its content, and `/etc/devbox/env` is never
printed.

## override

`devbox override` lists the overrides of this box: everything where it departs
from what the image ships, where that lives, and an `undo:` line with the
command that goes back to the default. It is the first thing to read when the
box behaves differently from another one built from the same image.

```bash
devbox override                                    # the list, by kind
devbox override --diff                             # every file override, as a unified diff
devbox override --diff ~/.config/mise/config.toml  # one file
```

What it reports, and how it knows:

- the seeded config (the `SEEDS` table of `dev-box-seed`) that differs from the
  version in `/etc/devbox/`; a file equal to its reference copy in
  `~/.config/dev-box/seed/` is not the user's doing and is left out. For the
  mise config, the tools added, removed or pinned to another version;
- the files of `~/.config/dev-box/overrides/`, whether they replace a dotarchy
  file, and whether `devbox sync` has applied them yet;
- the dotfiles changed or deleted since the last `devbox sync` (compared with
  the dotarchy clone, nvim left out), which the next sync overwrites; the
  `undo:` line also gives the copy into `overrides/` that keeps the change;
- `~/.config/dev-box/dev-envs/`, the scripts in `~/.local/bin` that shadow a
  command of `/usr/local/bin` or `/usr/bin`, the default agent, the packages
  of `devbox pkg`;
- the `.env` settings the box can see from any shell: `TS_DISABLE`,
  `DEV_ENVS` and `LLM_PROXY_URL` (from `/etc/devbox/env`), `PODMAN_ENABLE`
  (`/etc/devbox/podman.state`), `DOTARCHY_*` (`/etc/devbox/dotarchy.env`),
  `USER_NAME`, `USER_SHELL`, `TS_HOSTNAME`, and `PROJECTS_DIR` when the home
  is at `./data/home`;
- what `compose.override.yaml` adds to the container, read from the kernel:
  extra volumes (`/proc/self/mountinfo`), `mem_limit` and `cpus` (cgroup v2),
  devices beyond `/dev/net/tun`, capabilities added or dropped, and the
  `security_opt` of the podman block (seccomp, `/proc/sys` writable, AppArmor
  where it is active).

Variables that only PID 1 sees (`UPDATE_CHECK_INTERVAL`,
`MISE_INSTALL_ON_START`, `TS_EXTRA_ARGS`, ...) are not listed: an SSH session
cannot read them. Nothing is written and nothing goes over the network; the
`undo:` lines are printed, never run.

## motd

`devbox motd` prints the line you see when you land in the box: a command of
the box drawn at random, and what it does, plus a yellow line when an update is
waiting, and one when the `DEV_ENVS` environments are still installing or
failed. It is sourced at login by `/etc/devbox/updates-motd.sh`, once per tmux
session and once per shell elsewhere.

```bash
devbox motd    # print it again
```

It reads nothing but the box: no network, no cache, a few milliseconds. The
commands come from the `TIPS` array at the top of the script,
`command|what it does`, with a third field `tailscale` on the ones that stay
out when `TS_DISABLE=true`; `shuf` draws one. Adding a command is adding a line
there. The updates line is a count of `~/.cache/dev-box/updates`; the detail is
in `devbox check` and `devbox status`. The `DEV_ENVS` line is the first line of
`~/.cache/dev-box/dev-envs`, which the entrypoint writes at start and removes
once every environment is installed.

The first login after an update prints the notes of the new releases above
that line, three at most, through `dev-box-changelog --new`. See `changelog`.

## changelog

`devbox changelog` prints the release notes of the dev-box repository, read
live from its GitHub releases: one per `v*` tag, written in the annotation of
the tag.

```bash
devbox changelog          # the 3 latest releases, up to the one this box runs
devbox changelog -n 10    # the 10 latest
devbox changelog --all    # all of them
devbox changelog --upcoming   # the releases after this image
```

The notes are kept in `~/.cache/dev-box/releases.md`: `devbox check` refreshes
it in the background, `devbox changelog` refreshes it on every call and falls
back on it when GitHub is out of reach. `GITHUB_TOKEN` avoids the rate limit
of the API. `devbox check --image` says whether a newer image exists at all.

The version of the image whose notes you were shown is kept in
`~/.config/dev-box/changelog-seen`. When the box runs a newer one, the login
shows the releases in between (three at most, one line each: the first line of
their notes) once, from the cache, without touching the network, then records
the version. `devbox changelog` has the full notes. The entrypoint
marks a brand new home as seen.

## tour

`devbox tour` walks through the box in a dozen steps: the image and the home,
`devbox`, `status`, `dev-env`, `agent`, `pkg`, `dbs`, updates, the tailnet,
this skill, the overrides, and where a change belongs. Each step offers to
run the real command under your eyes. Nothing is installed by the tour
itself. The `dbs` step only shows when podman is on, the tailnet step only
with Tailscale; the overrides and repository steps print links into the
repository the image was built from (`/etc/devbox/release`), to `docs/customization.md`,
`architecture.md`, `extending.md` and `AGENTS.md`.

```bash
devbox tour           # step by step, with gum
devbox tour --text    # the whole content at once, no questions
```

The first login of a new home proposes it once: the entrypoint writes
`~/.config/dev-box/tour-pending`, `/etc/devbox/updates-motd.sh` calls
`dev-box-tour --offer`, which removes the flag then asks. A migration lays
the flag once on the homes that predate the tour.

## migrate

Migrations are small scripts in `/usr/share/devbox/migrations/`, named
`<YYYYMMDDHHMMSS>-<what>.sh`. They repair an existing home after an image
change the seed cannot handle on its own. Each one runs once, as the user, in
name order. The journal is `~/.config/dev-box/migrations`, one name per line.

```bash
devbox migrate                      # terminal: a menu; otherwise run what is pending
devbox migrate --run                # run what is pending, no menu
devbox migrate --pending            # list it, change nothing
devbox migrate --list               # all of them, with their state
devbox migrate --mark-done <name>   # acknowledge one without running it
```

The entrypoint runs it at every start, right after the seed. That is the only
automatic thing in the box, and it is deliberate: a migration ships with the
image that needs it. A brand new home has every migration marked as played
without running any. See `updates.md`, and `extending.md` to write one.

## mise-install

```bash
devbox mise-install                 # menu: write, list or remove
devbox mise-install <package> [command [binary]]
devbox mise-install --list
devbox mise-install --remove <command>
```

It writes `~/.local/bin/<command>`, a four line wrapper that runs
`mise use -g --quiet <package>` and then `mise x <package> -- <binary>`, with
`MISE_MINIMUM_RELEASE_AGE=0`. The image already ships that wrapper for
`claude`, `pi`, `omp`, `opencode` and `codex`; this is for everything else
(`gemini`, `crush`, `copilot`, and so on). `~/.local/bin` precedes
`/usr/local/bin` on the `PATH`, so a wrapper written here shadows the shipped
one of the same name. Wrappers written this way carry a
`# dev-box-mise-install` marker line, which is what `--list` and `--remove`
recognize; nothing else in `~/.local/bin` is ever touched.

## pkg

```bash
devbox pkg                      # menu: add, install, drop, list, restore
devbox pkg add <packages...>    # pacman -S --needed, then remember
devbox pkg drop <packages...>   # pacman -Rs, then forget
devbox pkg list                 # the list, and whether each one is installed
devbox pkg install              # fuzzy picker (fzf) over the Arch repositories
devbox pkg restore              # reinstall whatever is missing
```

The list is `~/.config/dev-box/packages`, one name per line, sorted, in the
persistent home. The entrypoint reinstalls what is missing at every start, in
the background. This is how a pacman package survives a rebuild without a
commit. Only packages: a config file edited in `/etc` is not tracked and does
not come back. Anything that must really last belongs in the `Dockerfile`.

## tailscale

```bash
devbox tailscale                # menu: send (online machine, then a file), receive, status
devbox tailscale send <machine> <file...>
devbox tailscale send <file...>  # no machine: a gum menu picks one among the peers online
devbox tailscale receive [--once] [directory]
devbox tailscale status
```

Taildrop, plus the state of the link. `send` without a machine needs a
terminal for the menu; it is what the `c t` chord of yazi runs on the
selected files (`~/.config/yazi/keymap.toml`, seeded). `receive` loops on
`tailscale file get --wait`, saving into `~/inbox` by default, and `--once`
returns after the first delivery. With `TS_DISABLE=true` there is no tailnet,
so every subcommand says so and exits 1. Taildrop works with Headscale 0.23 and
later, between machines of the same user.

## serve

```bash
devbox serve                    # menu: publish, tcp, status, off
devbox serve <port>             # listen on <port>, proxy to 127.0.0.1:<port>
devbox serve 8080:3000          # listen on 8080, proxy to 127.0.0.1:3000
devbox serve --on 8080 3000     # the same thing, written out
devbox serve --tcp 5433:5432    # raw TCP passthrough instead of http
devbox serve status             # what this box serves right now
devbox serve off [port|all]     # stop one mapping, or every one of them
```

A wrapper around `tailscale serve`, in plain http only: Headscale does not
implement the HTTPS feature, so the default https mode answers
`error 501 Not Implemented`, and Funnel is out for the same reason. What is
served is reachable from the tailnet only, at the URL the command prints,
`http://dev-box.home.arpa:3000/`. A single port means the same port on both
sides; in a pair, the first one is what the tailnet sees and the second is the
port the app listens on inside the box.

A server already bound to `0.0.0.0` in the box needs none of this: it answers
on `http://<TS_HOSTNAME>:<port>` as soon as the Headscale policy allows the
port. `devbox serve` is for a server bound to `127.0.0.1`, or to publish it on
another port. Running it as the user needs the tailnet operator to be set,
which `tailscale up --operator` does at every start; on a box that has not
restarted since, the command falls back to `sudo` once and says so. With
`TS_DISABLE=true` there is no tailnet, so it says so and exits 1.

## What is not a devbox command

The host owns the container. These run on the machine hosting it, never in
here, and the box can only print them:

```
just up        just rebuild     just down      just status
just backup    just restore     just update
```

`just update <what>` simply runs `dev-box-update <what>` in the box.
