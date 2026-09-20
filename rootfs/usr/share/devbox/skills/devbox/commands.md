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

PHP, Laravel, Symfony and OCaml are deliberately absent: upstream they need
pacman packages or opam, both of which would be lost on the next rebuild.

## What is not a devbox command

The host owns the container. These run on the machine hosting it, never in
here, and the box can only print them:

```
just up        just rebuild     just down      just status
just backup    just restore     just update
```

`just update <what>` simply runs `dev-box-update <what>` in the box.
