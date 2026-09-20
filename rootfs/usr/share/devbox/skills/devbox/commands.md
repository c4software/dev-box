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

Every command is still on `PATH` under its own name, and that is the name to
use in scripts and in the `justfile`: `devbox update` and `dev-box-update` are
the same binary.

## The commands

| `devbox` | Binary | Does |
|---|---|---|
| `status` | `dev-box-status` | image commit and repo, Tailscale or sshd, podman, mise tools, pending updates. Read only. |
| `check` | `dev-box-check-updates` | looks for what could be updated and writes the flag. Installs nothing. |
| `update` | `dev-box-update` | `[dotfiles\|tools\|seed\|all]`, default `all`. The only command that installs. |
| `seed` | `dev-box-seed` | lays down the config shipped by the image. `--check` to look, `--force [path]` to take a new version. |
| `sync` | `dotarchy-sync` | clones or updates the dotfiles repo and applies the config. Never runs its install scripts. |
| `dev-env` | `dev-box-dev-env` | installs a dev environment with mise. `--list`, or names as arguments, or a menu. |
| `dbs` | `dev-box-dbs` | starts a development database in a podman container. `--list`, `--start`, `--stop`, `--remove [--purge]`, or names, or a menu. |

`dev-box-podman` carries `# devbox:hidden=true`: it is the wrapper behind the
`docker` and `podman` symlinks, not something a user calls. It stays routable,
it just does not clutter the menu.

## Reading a command

They are short bash scripts. Reading one is faster than guessing:

```bash
cat $(which dev-box-update)
cat $(which dev-box-seed)      # the SEEDS table is at the top
cat $(which dev-box-dev-env)   # the ENVS list is at the top
```

## dev-env

`devbox dev-env` installs development environments with mise and nothing else:
no pacman, no `curl | sh`. Everything it installs is declared in
`~/.config/mise/config.toml`, so it survives a rebuild and is upgraded by
`devbox update tools`.

```bash
devbox dev-env --list      # what is on offer
devbox dev-env node go     # install these two
devbox dev-env             # menu, multiple selection
```

Re-running on an environment already installed is harmless.

PHP is baked into the image (pacman: php, composer, php-sqlite, php-gd,
php-sodium, xdebug, extensions enabled at build); `dev-env php` only checks it,
`laravel` and `symfony` add their installer on top. OCaml is absent: upstream it
needs opam, which would be lost on the next rebuild.

## dbs

`devbox dbs` runs development databases in rootless podman containers inside the
box, with the same images and development options as Omarchy's
`omarchy-install-docker-dbs` on the host.

```bash
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

## What is not a devbox command

The host owns the container. These run on the machine hosting it, never in
here, and the box can only print them:

```
just up        just rebuild     just down      just status
just backup    just restore     just update
```

`just update <what>` simply runs `dev-box-update <what>` in the box.
