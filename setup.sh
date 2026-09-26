#!/bin/sh
# Installs a dev-box from the published image, without cloning the repo and
# without building anything:
#
#   curl -fsSL https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh | sh
#   wget -qO- https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh | sh
#
# Options go after `sh -s --`, for instance:
#
#   curl -fsSL .../setup.sh | sh -s -- --yes --access ssh --ssh-key ~/.ssh/id_ed25519.pub
#
# It downloads compose.yaml, .env.example, compose.override.example.yaml and
# the backup scripts into an install directory (~/dev-box by
# default), writes .env from .env.example with the answers to a few questions,
# pulls the image and starts the box. Run again on the same directory, it
# refreshes those files and pulls the latest image, and never touches .env,
# compose.override.yaml or data/.
#
# Needs only a POSIX sh, curl or wget, and Docker with the Compose plugin.
# `sh setup.sh --help` lists the options and their environment variables.
set -eu

REPO_SLUG="c4software/dev-box"
DEFAULT_IMAGE="ghcr.io/c4software/dev-box:latest"
# Files needed to run the box, relative to the root of the repo.
SHIPPED="compose.yaml .env.example compose.override.example.yaml scripts/backup.sh scripts/restore.sh"

usage() {
  cat <<'TXT'
dev-box setup: install a dev-box from the published image, without a clone.

Usage: sh setup.sh [options]
       curl -fsSL https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh | sh -s -- [options]

With no option, it asks its questions on the terminal. Each option can also be
given as an environment variable (in brackets). --yes takes the defaults for
everything that was not given, and asks nothing.

  --dir DIR             install directory, default ~/dev-box       [DEVBOX_DIR]
  --user NAME           Unix user inside the box, default dev      [DEVBOX_USER]
  --access MODE         tailscale (default) or ssh                 [DEVBOX_ACCESS]
  --hostname NAME       Tailscale hostname, default dev-box        [DEVBOX_HOSTNAME]
  --login-server URL    Tailscale control server, or your Headscale [DEVBOX_LOGIN_SERVER]
  --authkey KEY         Tailscale auth key, empty prints a login URL [DEVBOX_AUTHKEY]
  --ssh-key KEY|FILE    public key(s) for --access ssh, a key or a .pub file,
                        default the first of ~/.ssh/id_{ed25519,ecdsa,rsa}.pub [DEVBOX_SSH_KEY]
  --ssh-port PORT       host port for --access ssh, default 2222   [DEVBOX_SSH_PORT]
  --ssh-bind ADDR       host address for it, default 127.0.0.1 (0.0.0.0: the LAN) [DEVBOX_SSH_BIND]
  --tz ZONE             timezone, default the host's               [DEVBOX_TZ]
  --projects-dir DIR    host directory mounted at ~/projets, default ./data/projets [DEVBOX_PROJECTS_DIR]
  --github-token TOKEN  GitHub token with no scope, recommended    [DEVBOX_GITHUB_TOKEN]
  --dev-envs "A B"      devbox dev-env names installed at first start, e.g. "node python" [DEVBOX_DEV_ENVS]
  --podman / --no-podman  rootless podman inside the box, off by default:
                        it loosens the isolation of the container [DEVBOX_PODMAN=yes|no]
  --image IMAGE         image to run, default ghcr.io/c4software/dev-box:latest [DEVBOX_IMAGE]
  --ref REF             branch or tag of the repo to take the files from, default main [DEVBOX_REF]
  --base-url URL|DIR    where to take the files from instead of GitHub (a local
                        directory works, for testing)          [DEVBOX_BASE_URL]
  --no-start            write the files, pull and start nothing [DEVBOX_NO_START=1]
  -y, --yes             ask nothing, take the defaults          [DEVBOX_YES=1]
  -h, --help            this help

On an existing install (a .env in the directory), it offers to update instead:
refresh the shipped files, pull the image, restart the box.
TXT
}

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# --- Options: flags first, then the environment, then the defaults ---
opt_dir="${DEVBOX_DIR:-}"
opt_user="${DEVBOX_USER:-}"
opt_access="${DEVBOX_ACCESS:-}"
opt_hostname="${DEVBOX_HOSTNAME:-}"
opt_login_server="${DEVBOX_LOGIN_SERVER:-}"
opt_authkey="${DEVBOX_AUTHKEY:-}"
opt_ssh_key="${DEVBOX_SSH_KEY:-}"
opt_ssh_port="${DEVBOX_SSH_PORT:-}"
opt_ssh_bind="${DEVBOX_SSH_BIND:-}"
opt_tz="${DEVBOX_TZ:-}"
opt_projects="${DEVBOX_PROJECTS_DIR:-}"
opt_token="${DEVBOX_GITHUB_TOKEN:-}"
opt_dev_envs="${DEVBOX_DEV_ENVS:-}"
opt_podman="${DEVBOX_PODMAN:-}"
opt_image="${DEVBOX_IMAGE:-}"
opt_ref="${DEVBOX_REF:-main}"
opt_base_url="${DEVBOX_BASE_URL:-}"
opt_no_start="${DEVBOX_NO_START:-0}"
opt_yes="${DEVBOX_YES:-0}"
# Which of the token-like values were given at all (an empty one is a choice)
given_authkey=0
[ -n "${DEVBOX_AUTHKEY+x}" ] && given_authkey=1
given_token=0
[ -n "${DEVBOX_GITHUB_TOKEN+x}" ] && given_token=1
given_dev_envs=0
[ -n "${DEVBOX_DEV_ENVS+x}" ] && given_dev_envs=1

while [ $# -gt 0 ]; do
  arg="$1"
  shift
  val=""
  case "$arg" in
    --*=*)
      val="${arg#*=}"
      arg="${arg%%=*}"
      ;;
    --dir | --user | --access | --hostname | --login-server | --authkey | --ssh-key | \
      --ssh-port | --ssh-bind | --tz | --projects-dir | --github-token | --dev-envs | \
      --image | --ref | --base-url)
      [ $# -gt 0 ] || die "$arg needs a value (sh setup.sh --help)"
      val="$1"
      shift
      ;;
  esac
  case "$arg" in
    --dir) opt_dir="$val" ;;
    --user) opt_user="$val" ;;
    --access) opt_access="$val" ;;
    --hostname) opt_hostname="$val" ;;
    --login-server) opt_login_server="$val" ;;
    --authkey) opt_authkey="$val" given_authkey=1 ;;
    --ssh-key) opt_ssh_key="$val" ;;
    --ssh-port) opt_ssh_port="$val" ;;
    --ssh-bind) opt_ssh_bind="$val" ;;
    --tz) opt_tz="$val" ;;
    --projects-dir) opt_projects="$val" ;;
    --github-token) opt_token="$val" given_token=1 ;;
    --dev-envs) opt_dev_envs="$val" given_dev_envs=1 ;;
    --podman) opt_podman=yes ;;
    --no-podman) opt_podman=no ;;
    --image) opt_image="$val" ;;
    --ref) opt_ref="$val" ;;
    --base-url) opt_base_url="$val" ;;
    --no-start) opt_no_start=1 ;;
    -y | --yes) opt_yes=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unknown option: $arg (sh setup.sh --help)" ;;
  esac
done

[ -n "$opt_base_url" ] || opt_base_url="https://raw.githubusercontent.com/$REPO_SLUG/$opt_ref"

# --- Terminal: questions are read from /dev/tty, so they work under curl | sh ---
interactive=0
if [ "$opt_yes" != "1" ] && (: </dev/tty) 2>/dev/null; then
  interactive=1
fi

# ask "Question" "default": prints the answer, the default on an empty line.
ask() {
  printf '%s [%s]: ' "$1" "$2" >/dev/tty
  IFS= read -r reply </dev/tty || reply=""
  [ -n "$reply" ] || reply="$2"
  printf '%s' "$reply"
}

# ask_secret "Question": same, nothing echoed, empty by default.
ask_secret() {
  printf '%s (hidden, empty for none): ' "$1" >/dev/tty
  stty -echo </dev/tty 2>/dev/null || true
  IFS= read -r reply </dev/tty || reply=""
  stty echo </dev/tty 2>/dev/null || true
  printf '\n' >/dev/tty
  printf '%s' "$reply"
}

# ask_yn "Question" y|n: status 0 for yes.
ask_yn() {
  if [ "$2" = y ]; then hint="Y/n"; else hint="y/N"; fi
  printf '%s [%s]: ' "$1" "$hint" >/dev/tty
  IFS= read -r reply </dev/tty || reply=""
  [ -n "$reply" ] || reply="$2"
  case "$reply" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

expand_home() {
  case "$1" in
    \~) printf '%s' "$HOME" ;;
    \~/*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# --- Prerequisites ---
say "dev-box setup"
say ""
say "Checking the prerequisites"

os="$(uname -s 2>/dev/null || echo unknown)"
on_windows=0
case "$os" in
  MINGW* | MSYS* | CYGWIN*) on_windows=1 ;;
esac
on_wsl=0
if [ "$os" = Linux ] && grep -qi microsoft /proc/version 2>/dev/null; then
  on_wsl=1
fi

if command -v curl >/dev/null 2>&1; then
  downloader=curl
elif command -v wget >/dev/null 2>&1; then
  downloader=wget
else
  die "neither curl nor wget is installed: install one of them and run this again"
fi

command -v docker >/dev/null 2>&1 || die "docker is not installed.
  Linux: the Docker Engine, https://docs.docker.com/engine/install/
  macOS and Windows: Docker Desktop, https://docs.docker.com/desktop/
  Then run this again."

docker compose version >/dev/null 2>&1 || die "the Docker Compose plugin is missing (docker compose version fails).
  The old standalone docker-compose is not enough. Install the plugin:
  https://docs.docker.com/compose/install/linux/ (Docker Desktop ships it)."

if ! info_err="$(docker info 2>&1 >/dev/null)"; then
  case "$info_err" in
    *"permission denied"* | *"Permission denied"*)
      die "Docker is installed but this user cannot reach it (permission denied).
  Add yourself to the docker group, then log out and back in:
    sudo usermod -aG docker \"\$USER\"
  Not with sudo: the box would be installed in root's home." ;;
    *)
      die "the Docker daemon does not answer.
  Start Docker Desktop, or the service (sudo systemctl start docker), then run this again.
  docker info said: $(printf '%s' "$info_err" | head -n 1)" ;;
  esac
fi

arch="$(docker info --format '{{.Architecture}}' 2>/dev/null || echo unknown)"
case "$arch" in
  x86_64 | amd64 | aarch64 | arm64) ;;
  *) warn "the image is published for amd64 and arm64, Docker reports '$arch': the pull may fail" ;;
esac

say "  $downloader, docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?'), compose $(docker compose version --short 2>/dev/null || echo '?'), $arch: fine"

# fetch <path in the repo> <destination>
fetch() {
  case "$opt_base_url" in
    /* | ./* | ../* | file://*)
      src="${opt_base_url#file://}/$1"
      [ -f "$src" ] || return 1
      cp "$src" "$2"
      ;;
    *)
      if [ "$downloader" = curl ]; then
        curl -fsSL --retry 3 -o "$2" "$opt_base_url/$1"
      else
        wget -q -O "$2" "$opt_base_url/$1"
      fi
      ;;
  esac
}

# --- Install directory ---
say ""
dir_default="$HOME/dev-box"
if [ -z "$opt_dir" ] && [ "$interactive" = 1 ]; then
  opt_dir="$(ask "Install directory (compose file, .env, and data/ with your home)" "$dir_default")"
fi
[ -n "$opt_dir" ] || opt_dir="$dir_default"
opt_dir="$(expand_home "$opt_dir")"
mkdir -p "$opt_dir" || die "cannot create $opt_dir"
DIR="$(cd "$opt_dir" && pwd)"

if [ -f "$DIR/Dockerfile" ]; then
  die "$DIR is a clone of the dev-box repo, which builds its own image.
  Run docker compose up -d --build there, or pick another directory with --dir."
fi

if [ "$on_windows" = 1 ]; then
  warn "Git Bash on Windows: data/ lands on the Windows file system, which is slow
  through Docker Desktop and loses the Unix file permissions. Running this same
  command inside WSL 2 (Ubuntu), with a directory in the Linux home, works better."
fi
case "$DIR" in
  /mnt/[a-z]/*)
    [ "$on_wsl" = 1 ] && warn "$DIR is on the Windows drive: slow through WSL. A directory under ~ is better."
    ;;
esac

mode=install
if [ -f "$DIR/.env" ]; then
  mode=update
elif [ -n "$(ls -A "$DIR" 2>/dev/null)" ] && [ ! -f "$DIR/compose.yaml" ] && [ ! -d "$DIR/data" ]; then
  die "$DIR is not empty and holds no dev-box: pick an empty or new directory with --dir"
fi

# --- Shipped files: replaced only when the installed copy is still the one
# this script wrote (checksums in .setup-shipped). A copy edited by hand is
# never overwritten: the new version goes next to it as <file>.new ---
tmp="$DIR/.setup-tmp"
rm -rf "$tmp"
mkdir -p "$tmp/scripts"
trap 'rm -rf "$tmp"' EXIT
trap 'stty echo </dev/tty 2>/dev/null; exit 130' INT TERM

say "Downloading the files from $opt_base_url"
for f in $SHIPPED; do
  fetch "$f" "$tmp/$f" || die "cannot download $opt_base_url/$f
  Check the network, or the --ref/--base-url given."
done

record="$DIR/.setup-shipped"
sum_of() { cksum <"$1" | awk '{ print $1 "-" $2 }'; }
recorded_sum() {
  [ -f "$record" ] || return 0
  awk -v f="$1" '$2 == f { print $1 }' "$record"
}

new_record="$tmp/.setup-shipped"
: >"$new_record"
for f in $SHIPPED; do
  new_sum="$(sum_of "$tmp/$f")"
  dest="$DIR/$f"
  mkdir -p "$(dirname "$dest")"
  if [ ! -f "$dest" ]; then
    cp "$tmp/$f" "$dest"
    say "  $f: added"
  else
    cur_sum="$(sum_of "$dest")"
    if [ "$cur_sum" = "$new_sum" ]; then
      say "  $f: up to date"
    elif [ "$cur_sum" = "$(recorded_sum "$f")" ]; then
      cp "$tmp/$f" "$dest"
      say "  $f: updated"
    elif [ "$new_sum" = "$(recorded_sum "$f")" ]; then
      say "  $f: edited here, kept (nothing new upstream)"
    else
      cp "$tmp/$f" "$dest.new"
      say "  $f: edited here, kept; the new version is in $f.new, merge it by hand"
    fi
  fi
  printf '%s %s\n' "$new_sum" "$f" >>"$new_record"
done
chmod +x "$DIR/scripts/backup.sh" "$DIR/scripts/restore.sh"
cp "$new_record" "$record"

# Container name: fixed in compose.yaml, one box of this kind per host.
container="$(sed -n 's/^[[:space:]]*container_name:[[:space:]]*//p' "$DIR/compose.yaml" | head -n 1 | tr -d "\"'")"
[ -n "$container" ] || container=dev-box

# env_get KEY: the value of KEY in .env, quotes removed (single-line values).
env_get() {
  sed -n "s/^$1=//p" "$DIR/.env" | tail -n 1 | sed "s/^'\(.*\)'\$/\1/; s/^\"\(.*\)\"\$/\1/"
}

# env_set KEY VALUE: rewrites the KEY= line of .env.new (appended when missing).
env_quote() {
  [ -n "$1" ] || return 0
  case "$1" in
    *"'"*) die "a value cannot contain a single quote: $1" ;;
  esac
  if printf '%s' "$1" | grep -q '^[A-Za-z0-9_./:@+,=-]*$' && [ "$(printf '%s\n' "$1" | wc -l)" -le 1 ]; then
    printf '%s' "$1"
  else
    printf "'%s'" "$1"
  fi
}
env_set() {
  line="$1=$(env_quote "$2")"
  LINE="$line" KEY="$1" awk '
    BEGIN { done = 0 }
    !done && index($0, ENVIRON["KEY"] "=") == 1 { print ENVIRON["LINE"]; done = 1; next }
    { print }
    END { if (!done) print ENVIRON["LINE"] }
  ' "$DIR/.env.new" >"$DIR/.env.tmp"
  mv "$DIR/.env.tmp" "$DIR/.env.new"
}

# Another container with the same name, started from somewhere else (a clone).
# Docker Desktop on Windows records the directory as C:\\..., Git Bash as /c/...
norm_path() {
  if [ "$on_windows" = 1 ]; then
    printf '%s' "$1" | tr '\134' '/' | tr '[:upper:]' '[:lower:]'
  else
    printf '%s' "$1"
  fi
}
check_container_clash() {
  found="$(docker ps -a --format '{{.Names}}|{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null |
    awk -F '|' -v n="$container" '$1 == n { print "found|" $2; exit }')"
  [ -n "$found" ] || return 0
  other="${found#found|}"
  here="$DIR"
  if [ "$on_windows" = 1 ]; then
    here="$(cd "$DIR" && { pwd -W 2>/dev/null || pwd; })"
  fi
  [ "$(norm_path "$other")" = "$(norm_path "$here")" ] && return 0
  die "a container named $container already exists${other:+, started from $other}.
  compose.yaml names the container $container, so only one such box runs per host.
  Update that one where it lives, or remove it first (docker compose down in its directory)."
}

# --- Update of an existing install ---
if [ "$mode" = update ]; then
  say ""
  say "Existing install found in $DIR: .env, compose.override.yaml and data/ are left as they are."
  image_in_env="$(env_get DEVBOX_IMAGE)"
  if [ -z "$image_in_env" ]; then
    die "DEVBOX_IMAGE is empty in $DIR/.env, and this directory has no Dockerfile to build from.
  Set DEVBOX_IMAGE=$DEFAULT_IMAGE in it, then run this again."
  fi
  if [ "$opt_no_start" = 1 ]; then
    say "Files refreshed, nothing started (--no-start)."
    exit 0
  fi
  if [ "$interactive" = 1 ] && ! ask_yn "Pull the latest image ($image_in_env) and restart the box?" y; then
    say "Nothing else done. To update later: cd $DIR && docker compose pull && docker compose up -d"
    exit 0
  fi
  check_container_clash
  cd "$DIR"
  say "Pulling $image_in_env"
  docker compose pull
  docker image inspect "$image_in_env" >/dev/null 2>&1 || die "the image $image_in_env is not there after the pull"
  docker compose up -d --no-build
  say ""
  say "The box runs on the latest image. Your home and projects are untouched."
  say "  logs:     cd $DIR && docker compose logs -f"
  say "  in-box:   devbox update (dotfiles, tools, shipped config), devbox changelog"
  exit 0
fi

# --- New install: the questions ---
if [ -n "$(ls -A "$DIR/data/home" 2>/dev/null)" ]; then
  say ""
  say "$DIR/data/home already holds a home, from an earlier install whose .env is gone."
  say "The new box will start on it, nothing in it is erased."
  if [ "$interactive" = 1 ] && ! ask_yn "Continue with it?" y; then
    say "Stopped, nothing changed apart from the shipped files."
    exit 0
  fi
fi

example_get() {
  sed -n "s/^$1=//p" "$DIR/.env.example" | head -n 1 | sed "s/^'\(.*\)'\$/\1/; s/^\"\(.*\)\"\$/\1/"
}

host_tz() {
  if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
    printf '%s' "$TZ"
    return
  fi
  if [ -r /etc/timezone ]; then
    head -n 1 /etc/timezone
    return
  fi
  link="$(readlink /etc/localtime 2>/dev/null || true)"
  case "$link" in
    *zoneinfo/*)
      printf '%s' "${link#*zoneinfo/}"
      return
      ;;
  esac
  example_get TZ
}

default_ssh_key_file() {
  for k in id_ed25519 id_ecdsa id_rsa; do
    if [ -f "$HOME/.ssh/$k.pub" ]; then
      printf '%s' "$HOME/.ssh/$k.pub"
      return
    fi
  done
}

# read_keys KEY|FILE: the public keys, one per line, or an error.
read_keys() {
  src="$(expand_home "$1")"
  if [ -f "$src" ]; then
    keys="$(grep -v '^[[:space:]]*\(#.*\)\{0,1\}$' "$src" || true)"
  else
    keys="$1"
  fi
  [ -n "$keys" ] || return 1
  # every line a key type: ssh-ed25519, ssh-rsa, ecdsa-sha2-*, sk-*
  if printf '%s\n' "$keys" | grep -Evq '^(ssh-|ecdsa-|sk-)'; then return 1; fi
  printf '%s' "$keys"
}

say ""
if [ "$interactive" = 1 ]; then
  say "A few questions. Enter keeps the value in brackets; everything can be changed later in $DIR/.env."
  say ""
else
  say "No terminal to ask on (or --yes): the defaults and the given options are used."
fi

# User
[ -n "$opt_user" ] || { [ "$interactive" = 1 ] && opt_user="$(ask "Unix user inside the box" "$(example_get USER_NAME)")"; } || true
[ -n "$opt_user" ] || opt_user="$(example_get USER_NAME)"
printf '%s' "$opt_user" | grep -q '^[a-z_][a-z0-9_-]*$' || die "invalid user name: $opt_user (lowercase letters, digits, _ and -)"

# Timezone
if [ -z "$opt_tz" ]; then
  opt_tz="$(host_tz)"
  [ "$interactive" = 1 ] && opt_tz="$(ask "Timezone" "$opt_tz")"
fi

# Access
if [ -z "$opt_access" ] && [ "$interactive" = 1 ]; then
  say ""
  say "How will you connect to the box?"
  say "  tailscale: from any of your machines on your tailnet (Tailscale or Headscale account)"
  say "  ssh:       an SSH port published on this host, public key only, no account needed"
  opt_access="$(ask "Access (tailscale or ssh)" tailscale)"
fi
[ -n "$opt_access" ] || opt_access=tailscale
case "$opt_access" in
  tailscale | ssh) ;;
  *) die "--access is tailscale or ssh, not $opt_access" ;;
esac

ssh_keys=""
if [ "$opt_access" = tailscale ]; then
  [ -n "$opt_hostname" ] || { [ "$interactive" = 1 ] && opt_hostname="$(ask "Tailscale hostname of the box" "$(example_get TS_HOSTNAME)")"; } || true
  [ -n "$opt_login_server" ] || { [ "$interactive" = 1 ] && opt_login_server="$(ask "Control server (your Headscale URL, or Tailscale)" "$(example_get TS_LOGIN_SERVER)")"; } || true
  if [ "$given_authkey" = 0 ] && [ "$interactive" = 1 ]; then
    say "An auth key attaches the box on its own; without one, a login URL is printed to open once."
    opt_authkey="$(ask_secret "Tailscale auth key")"
  fi
else
  if [ -z "$opt_ssh_key" ]; then
    found="$(default_ssh_key_file)"
    if [ "$interactive" = 1 ]; then
      if [ -n "$found" ]; then
        opt_ssh_key="$(ask "Public key allowed in (a .pub file or the key itself)" "$found")"
      else
        say "No public key in ~/.ssh. Create one with: ssh-keygen -t ed25519"
        opt_ssh_key="$(ask "Public key allowed in (a .pub file or the key itself, empty for none)" "")"
      fi
    else
      opt_ssh_key="$found"
    fi
  fi
  if [ -n "$opt_ssh_key" ]; then
    ssh_keys="$(read_keys "$opt_ssh_key")" || die "not a public key, nor a file of public keys: $opt_ssh_key"
  else
    warn "no public key: sshd will not start. Add one to SSH_AUTHORIZED_KEYS in .env later,
  or get in with docker exec -it -u $opt_user $container zsh -l"
  fi
  [ -n "$opt_ssh_port" ] || { [ "$interactive" = 1 ] && opt_ssh_port="$(ask "SSH port on this host" "$(example_get SSH_PORT)")"; } || true
  [ -n "$opt_ssh_bind" ] || { [ "$interactive" = 1 ] && opt_ssh_bind="$(ask "Address it listens on (127.0.0.1: this machine only, 0.0.0.0: the LAN)" "$(example_get SSH_BIND)")"; } || true
fi
[ -n "$opt_ssh_port" ] || opt_ssh_port="$(example_get SSH_PORT)"
[ -n "$opt_ssh_bind" ] || opt_ssh_bind="$(example_get SSH_BIND)"
case "$opt_ssh_port" in
  "" | *[!0-9]*) die "invalid SSH port: $opt_ssh_port" ;;
esac
[ "$opt_ssh_port" -ge 1 ] && [ "$opt_ssh_port" -le 65535 ] || die "invalid SSH port: $opt_ssh_port"

# Optional extras
if [ "$given_token" = 0 ] && [ "$interactive" = 1 ]; then
  say ""
  say "A GitHub token with no scope avoids the GitHub API rate limit while tools install (recommended)."
  opt_token="$(ask_secret "GitHub token")"
fi
if [ "$given_dev_envs" = 0 ] && [ "$interactive" = 1 ]; then
  say ""
  say "Dev environments to install at the first start, space separated, empty for none."
  say "For instance: node python php go rust java laravel (devbox dev-env --list in the box shows them all)."
  opt_dev_envs="$(ask "Dev environments" "")"
fi
if [ -z "$opt_podman" ] && [ "$interactive" = 1 ]; then
  say ""
  say "Rootless podman runs docker commands inside the box, but it loosens the isolation"
  say "of the container (seccomp, /proc/sys and AppArmor opened)."
  if ask_yn "Turn podman on?" n; then opt_podman=yes; else opt_podman=no; fi
fi
case "$opt_podman" in
  yes | true | 1) opt_podman=yes ;;
  "" | no | false | 0) opt_podman=no ;;
  *) die "--podman takes yes or no, not $opt_podman" ;;
esac
[ -n "$opt_image" ] || opt_image="$DEFAULT_IMAGE"

# --- .env, written from .env.example ---
cp "$DIR/.env.example" "$DIR/.env.new"
env_set USER_NAME "$opt_user"
env_set TZ "$opt_tz"
[ -n "$opt_projects" ] && env_set PROJECTS_DIR "$opt_projects"
env_set DEVBOX_IMAGE "$opt_image"
if [ "$opt_access" = tailscale ]; then
  env_set TS_DISABLE false
  [ -n "$opt_hostname" ] && env_set TS_HOSTNAME "$opt_hostname"
  [ -n "$opt_login_server" ] && env_set TS_LOGIN_SERVER "$opt_login_server"
  env_set TS_AUTHKEY "$opt_authkey"
else
  env_set TS_DISABLE true
  env_set SSH_AUTHORIZED_KEYS "$ssh_keys"
fi
env_set SSH_PORT "$opt_ssh_port"
env_set SSH_BIND "$opt_ssh_bind"
env_set GITHUB_TOKEN "$opt_token"
env_set DEV_ENVS "$opt_dev_envs"
if [ "$opt_podman" = yes ]; then env_set PODMAN_ENABLE true; else env_set PODMAN_ENABLE false; fi
chmod 600 "$DIR/.env.new"
mv "$DIR/.env.new" "$DIR/.env"
say ""
say "Wrote $DIR/.env"

if [ "$opt_podman" = yes ]; then
  if [ -f "$DIR/compose.override.yaml" ]; then
    warn "compose.override.yaml already exists and is left alone: add the podman block
  of compose.override.example.yaml to it by hand, or podman will not start"
  else
    cat >"$DIR/compose.override.yaml" <<'YAML'
# Written by setup.sh because rootless podman was asked for (PODMAN_ENABLE=true
# in .env). Why each line is needed: compose.override.example.yaml.
services:
  dev-box:
    devices:
      - /dev/net/tun
      - /dev/fuse
    security_opt:
      - seccomp=unconfined
      - systempaths=unconfined
      - apparmor=unconfined
YAML
    say "Wrote $DIR/compose.override.yaml (the podman settings)"
  fi
fi

# The bind mounts, created by this user rather than by Docker as root.
mkdir -p "$DIR/data/home" "$DIR/data/tailscale"
projects="$(env_get PROJECTS_DIR)"
[ -n "$projects" ] || projects=./data/projets
case "$projects" in
  /*) mkdir -p "$projects" ;;
  *) mkdir -p "$DIR/$projects" ;;
esac

cd "$DIR"
docker compose config -q || die "docker compose rejects the configuration in $DIR, see above"

# --- What to do next ---
next_steps() {
  say ""
  say "Connect:"
  if [ "$opt_access" = tailscale ]; then
    say "  ssh $opt_user@$(env_get TS_HOSTNAME)          from any machine of your tailnet"
  else
    say "  ssh -p $opt_ssh_port $opt_user@127.0.0.1"
    [ "$opt_ssh_bind" = 0.0.0.0 ] && say "  ssh -p $opt_ssh_port $opt_user@<this host's address>   from the LAN"
  fi
  say "  docker exec -it -u $opt_user $container zsh -l   always works, on this host"
  say ""
  say "In $DIR:"
  say "  docker compose logs -f                        what the box is doing"
  say "  docker compose pull && docker compose up -d   update to the latest image"
  say "  run the install command again                 same, and refreshes compose.yaml"
  say "  edit .env, then docker compose up -d          change a setting"
  say "  docker compose down                           stop the box, data/ is kept"
  say "  scripts/backup.sh                             back up data/ (scripts/restore.sh to restore)"
  say ""
  say "Documentation: https://github.com/$REPO_SLUG/tree/main/docs"
  say ""
  say "Uninstall: cd $DIR && docker compose down --rmi all, then delete $DIR"
  say "  (that deletes your home and projects in data/; some files there belong to root: sudo rm -rf on Linux)"
}

if [ "$opt_no_start" = 1 ]; then
  say ""
  say "Nothing started (--no-start). To start: cd $DIR && docker compose pull && docker compose up -d"
  next_steps
  exit 0
fi

check_container_clash
say ""
say "Pulling $opt_image (a few minutes the first time)"
docker compose pull
docker image inspect "$opt_image" >/dev/null 2>&1 || die "the image $opt_image is not there after the pull"
say "Starting the box"
docker compose up -d --no-build

if [ "$opt_access" = tailscale ] && [ -z "$opt_authkey" ] && [ ! -s "$DIR/data/tailscale/tailscaled.state" ]; then
  say ""
  say "Waiting for the Tailscale login URL (up to 2 minutes)"
  url=""
  i=0
  while [ $i -lt 60 ]; do
    url="$(docker compose logs --no-color 2>/dev/null |
      awk '/To authenticate, visit/ { f = 1 } f && /https?:\/\// { for (i = 1; i <= NF; i++) if ($i ~ /^https?:\/\//) u = $i } END { print u }')"
    [ -n "$url" ] && break
    i=$((i + 1))
    sleep 2
  done
  if [ -n "$url" ]; then
    say "  Open this URL to attach the box to your tailnet, once:"
    say "    $url"
  else
    say "  Not printed yet: follow docker compose logs -f in $DIR, it shows the URL."
  fi
fi

say ""
say "The box is starting. The first start seeds your home, syncs the dotfiles and"
say "installs the tools in the background: a few minutes before everything is there."
next_steps
