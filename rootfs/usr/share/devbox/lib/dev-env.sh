# shellcheck shell=bash
# dev-box: the environments of `devbox dev-env`, found on disk. Sourced by
# dev-box-dev-env, and by every environment script run through it, not run.
#
# One environment is one file, <name>.sh, in one of two directories:
#   /usr/share/devbox/dev-envs      shipped with the image
#   ~/.config/dev-box/dev-envs      the user's own, kept across rebuilds; a
#                                   file here wins over the image's of the
#                                   same name
# The name is the file name without .sh: lowercase letters, digits, - and _.
#
# A file defines functions and runs nothing at the top level:
#   details        required. First line: the short description shown by the
#                  menu and --list. The lines after it: the long text of
#                  --info (what is installed, what a removal leaves).
#   install        required. Installs the environment; running it twice is
#                  harmless.
#   uninstall      required. Removes what the environment itself brought,
#                  never project data.
#   is_installed   optional. Exits 0 when the environment is there. Without
#                  it: the tool <name> is declared in the global mise config.
#   is_supported   optional. Exits 0 when the environment can be installed on
#                  this machine; otherwise prints the reason on one line and
#                  exits 1. Without it: supported everywhere. An unsupported
#                  environment is left out of the menu and --list, refused by
#                  an install, skipped by --if-missing.
#
# Each function runs in its own bash process, with `set -euo pipefail`: a
# failing command stops it, and the functions of two files never meet. What
# this file defines is available to them: log, err, declared, unuse, and
# dev_env to reach another environment (`dev_env install php`).

# Brand new releases are not quarantined here: when you ask for an environment,
# you want it now.
export MISE_MINIMUM_RELEASE_AGE=0

DEV_ENV_LIB="${BASH_SOURCE[0]}"
DEV_ENV_SYSTEM_DIR="${DEV_ENV_SYSTEM_DIR:-/usr/share/devbox/dev-envs}"
DEV_ENV_USER_DIR="${DEV_ENV_USER_DIR:-$HOME/.config/dev-box/dev-envs}"
MISE_CFG="$HOME/.config/mise/config.toml"

log() { printf '\033[1m[dev-box-dev-env]\033[0m %s\n' "$*"; }
err() { echo "dev-box-dev-env: $*" >&2; }

# --- Discovery ---------------------------------------------------------------

# DEV_ENV_NAMES: every name, sorted. DEV_ENV_FILES[name]: the file that wins.
# shellcheck disable=SC2034 # read by dev-box-dev-env
declare -a DEV_ENV_NAMES=()
declare -A DEV_ENV_FILES=()

dev_env_load() {
  local f name
  DEV_ENV_NAMES=()
  DEV_ENV_FILES=()
  # The user's directory first: the first file seen for a name is the one kept.
  for f in "$DEV_ENV_USER_DIR"/*.sh "$DEV_ENV_SYSTEM_DIR"/*.sh; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .sh)"
    [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || continue
    [ -n "${DEV_ENV_FILES[$name]:-}" ] && continue
    DEV_ENV_FILES[$name]="$f"
  done
  [ "${#DEV_ENV_FILES[@]}" -gt 0 ] || return 0
  # shellcheck disable=SC2034 # read by dev-box-dev-env
  mapfile -t DEV_ENV_NAMES < <(printf '%s\n' "${!DEV_ENV_FILES[@]}" | sort)
}

dev_env_exists() { [ -n "${DEV_ENV_FILES[$1]:-}" ]; }

# --- Running a function of an environment ------------------------------------

# dev_env_call <name> <function>: a fresh bash process, so that `set -e` holds
# even when the caller tests the result, and nothing leaks between files.
dev_env_call() {
  local name="$1" fn="$2"
  dev_env_exists "$name" || {
    err "unknown environment '$name'"
    return 1
  }
  bash -euo pipefail -c '. "$1"; shift; dev_env_exec "$@"' dev-env \
    "$DEV_ENV_LIB" "$name" "${DEV_ENV_FILES[$name]}" "$fn"
}

# The inside of dev_env_call: load the file, check its shape, run the function.
# DEV_ENV_SELF is the environment running, for the scripts and dev_env.
dev_env_exec() {
  local file="$2" fn="$3" f
  DEV_ENV_SELF="$1"
  # shellcheck disable=SC2329 # the defaults, replaced by the script's own
  is_installed() { declared "$DEV_ENV_SELF"; }
  # shellcheck disable=SC2329
  is_supported() { return 0; }
  dev_env_load
  # shellcheck source=/dev/null
  . "$file"
  for f in details install uninstall; do
    declare -F "$f" >/dev/null || {
      err "$file: no $f function"
      return 1
    }
  done
  "$fn"
}

# One line for the list and the menu: installed (1 or 0), a tab, supported
# (1 or 0), a tab, the short description. One process per environment.
dev_env_summary() {
  local d
  d="$(details)"
  if is_installed >/dev/null 2>&1; then printf '1\t'; else printf '0\t'; fi
  if is_supported >/dev/null 2>&1; then printf '1\t'; else printf '0\t'; fi
  printf '%s\n' "${d%%$'\n'*}"
}

# dev_env_unsupported <name>: exits 0, the reason on stdout, when the
# environment cannot be installed on this machine.
dev_env_unsupported() {
  local why
  why="$(dev_env_call "$1" is_supported 2>&1)" && return 1
  printf '%s\n' "${why:-not available on this machine ($(uname -m))}"
}

# --- Helpers for the environment scripts -------------------------------------

# dev_env install|uninstall|is_installed <name>: another environment, the one
# this one sits on (laravel on php and node, phoenix on elixir).
dev_env() {
  local action="$1" name="$2"
  local why
  case "$action" in
  install)
    if why="$(dev_env_unsupported "$name")"; then
      err "$name, needed by ${DEV_ENV_SELF:-this environment}, is not available here: $why"
      return 1
    fi
    log "$name, needed by ${DEV_ENV_SELF:-this environment}"
    ;;
  uninstall | is_installed) ;;
  *)
    err "dev_env: unknown action '$action'"
    return 2
    ;;
  esac
  dev_env_call "$name" "$action"
}

# A tool is installed when it is declared in the global mise config: that is
# what `mise use -g` writes and `mise unuse -g` removes.
declared() {
  [ -f "$MISE_CFG" ] || return 1
  mise config get -f "$MISE_CFG" "tools.$1" >/dev/null 2>&1
}

# `mise unuse -g` removes the tools from the global config, then `mise prune`
# deletes the installed versions no tracked config needs any more (a project
# that pins go@1.26 in its own mise.toml keeps it). unuse would prune on its
# own, but it asks for confirmation on a terminal and skips silently without
# one, so the two steps are kept apart and prune answers yes. Both exit 0 on a
# tool that is not declared or already gone, so calling them twice is fine.
unuse() {
  mise unuse -g --no-prune "$@"
  mise prune --yes "$@"
}
