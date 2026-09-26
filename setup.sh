#!/bin/sh
# Installs a dev-box from the published image, without cloning the repo and
# without building anything:
#
#   curl -fsSL https://cours.brosseau.ovh/devbox.sh | sh
#
# Piping a download into sh is a bad habit: it runs code nobody read, and a
# truncated one if the download is cut. Better, download it first, read it,
# then run it:
#
#   curl -fsSLo devbox.sh https://cours.brosseau.ovh/devbox.sh
#   less devbox.sh
#   sh devbox.sh
#
# That address redirects to this file on GitHub:
# https://raw.githubusercontent.com/c4software/dev-box/main/setup.sh
#
# It takes no option: it asks its questions on the terminal, with gum
# (https://github.com/charmbracelet/gum) when it is installed, plain prompts
# otherwise. It downloads compose.yaml, .env.example,
# compose.override.example.yaml and the backup scripts from the main branch
# into an install directory (~/dev-box by default), writes .env from
# .env.example with the answers, then offers to pull
# ghcr.io/c4software/dev-box:latest and start the box. Run again on the same
# directory, it refreshes those files and offers to pull the latest image, and
# never touches .env, compose.override.yaml or data/.
#
# Needs only a POSIX sh, curl or wget, Docker with the Compose plugin, and a
# terminal.
#
# For testing a change before it is pushed, DEVBOX_SETUP_BASE_URL takes the
# files from somewhere else than GitHub main: another URL, or a local
# directory such as a clone (DEVBOX_SETUP_BASE_URL=$PWD sh setup.sh).
set -eu

REPO_SLUG="c4software/dev-box"
IMAGE="ghcr.io/c4software/dev-box:latest"
BASE_URL="${DEVBOX_SETUP_BASE_URL:-https://raw.githubusercontent.com/$REPO_SLUG/main}"
# Files needed to run the box, relative to the root of the repo.
SHIPPED="compose.yaml .env.example compose.override.example.yaml scripts/backup.sh scripts/restore.sh"

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[ $# -eq 0 ] || die "setup.sh takes no option: run it without any, it asks its questions"

# The questions are read from /dev/tty, not from stdin, so they work when the
# script is piped into sh.
(: </dev/tty) 2>/dev/null || die "no terminal to ask the questions on: run it from a terminal"
interrupted() {
  stty echo </dev/tty 2>/dev/null || true
  printf '\nerror: setup interrupted, nothing more done\n' >&2
  exit 130
}
trap interrupted INT TERM

# --- The questions: the only place that knows about gum. They use it when it
# is installed, plain prompts otherwise, read /dev/tty either way and print
# the answer on stdout. gum clears its prompt once answered, so the answer is
# echoed on the terminal to keep a trace of it ---
use_gum=0
command -v gum >/dev/null 2>&1 && use_gum=1

# gum_ask <gum args>: runs gum on the terminal; Ctrl-C or Esc stops the
# setup. The questions run in a command substitution, so the main shell is
# signalled rather than left to go on.
gum_ask() {
  st=0
  gum "$@" </dev/tty 2>/dev/tty || st=$?
  if [ "$st" -gt 1 ]; then
    kill -TERM "$$"
    exit 130
  fi
  return "$st"
}

# gum_failed, after reply="$(gum_ask ...)" failed: stops this subshell too when
# the setup was interrupted, takes an empty answer otherwise.
gum_failed() {
  st=$?
  [ "$st" -le 1 ] || exit "$st"
  reply=""
}

# ask "Question" "default": prints the answer, the default on an empty line.
# With gum the default is a placeholder, not a prefilled value, so typing
# replaces it rather than appending to it.
ask() {
  if [ "$use_gum" = 1 ]; then
    reply="$(gum_ask input --header "$1" --placeholder "$2" --width 0)" || gum_failed
    [ -n "$reply" ] || reply="$2"
    printf '%s: %s\n' "$1" "$reply" >/dev/tty
  else
    if [ -n "$2" ]; then printf '%s [%s]: ' "$1" "$2"; else printf '%s: ' "$1"; fi >/dev/tty
    IFS= read -r reply </dev/tty || reply=""
    [ -n "$reply" ] || reply="$2"
  fi
  printf '%s' "$reply"
}

# ask_secret "Question": same, nothing echoed, empty by default.
ask_secret() {
  if [ "$use_gum" = 1 ]; then
    reply="$(gum_ask input --password --header "$1 (hidden, empty for none)" --width 0)" || gum_failed
    if [ -n "$reply" ]; then shown="given"; else shown="none"; fi
    printf '%s: %s\n' "$1" "$shown" >/dev/tty
  else
    printf '%s (hidden, empty for none): ' "$1" >/dev/tty
    stty -echo </dev/tty 2>/dev/null || true
    IFS= read -r reply </dev/tty || reply=""
    stty echo </dev/tty 2>/dev/null || true
    printf '\n' >/dev/tty
  fi
  printf '%s' "$reply"
}

# ask_yn "Question" y|n: status 0 for yes.
ask_yn() {
  if [ "$use_gum" = 1 ]; then
    if [ "$2" = y ]; then gum_default=true; else gum_default=false; fi
    st=0
    gum_ask confirm "$1" --default="$gum_default" || st=$?
    if [ "$st" = 0 ]; then shown=yes; else shown=no; fi
    printf '%s %s\n' "$1" "$shown" >/dev/tty
    return "$st"
  fi
  if [ "$2" = y ]; then hint="Y/n"; else hint="y/N"; fi
  printf '%s [%s]: ' "$1" "$hint" >/dev/tty
  IFS= read -r reply </dev/tty || reply=""
  [ -n "$reply" ] || reply="$2"
  case "$reply" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ask_choice "Question" default choice...: prints one of the choices, asks
# again until the answer is one of them.
ask_choice() {
  question="$1" default="$2"
  shift 2
  if [ "$use_gum" = 1 ]; then
    reply="$(gum_ask choose --header "$question" --selected "$default" "$@")" || gum_failed
    [ -n "$reply" ] || reply="$default"
    printf '%s: %s\n' "$question" "$reply" >/dev/tty
    printf '%s' "$reply"
    return
  fi
  choices="$(printf '%s or ' "$@")"
  choices="${choices% or }"
  while :; do
    reply="$(ask "$question ($choices)" "$default")"
    for c in "$@"; do
      if [ "$reply" = "$c" ]; then
        printf '%s' "$reply"
        return
      fi
    done
    printf '  answer %s\n' "$choices" >/dev/tty
  done
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

# fetch_url URL: the body on stdout, or an error.
fetch_url() {
  if [ "$downloader" = curl ]; then
    curl -fsSL --retry 3 "$1"
  else
    wget -q -O - "$1"
  fi
}

# fetch <path in the repo> <destination>
fetch() {
  case "$BASE_URL" in
    /* | ./* | ../* | file://*)
      src="${BASE_URL#file://}/$1"
      [ -f "$src" ] || return 1
      cp "$src" "$2"
      ;;
    *) fetch_url "$BASE_URL/$1" >"$2" ;;
  esac
}

# --- Install directory ---
say ""
# shellcheck disable=SC2088 # a ~ shown to the user, expanded by expand_home
dir="$(expand_home "$(ask "Install directory (compose file, .env, and data/ with your home)" "~/dev-box")")"
mkdir -p "$dir" || die "cannot create $dir"
DIR="$(cd "$dir" && pwd)"
# The directory as shown in messages: ~ for the home, shorter to read.
# shellcheck disable=SC2088 # shown, never expanded
case "$DIR" in
  "$HOME"/*) SHOW_DIR="~/${DIR#"$HOME"/}" ;;
  *) SHOW_DIR="$DIR" ;;
esac

if [ -f "$DIR/Dockerfile" ]; then
  die "$SHOW_DIR is a clone of the dev-box repo, which builds its own image.
  Run docker compose up -d --build there, or run this again with another directory."
fi

if [ "$on_windows" = 1 ]; then
  warn "Git Bash on Windows: data/ lands on the Windows file system, which is slow
  through Docker Desktop and loses the Unix file permissions. Running this same
  command inside WSL 2 (Ubuntu), with a directory in the Linux home, works better."
fi
case "$DIR" in
  /mnt/[a-z]/*)
    [ "$on_wsl" = 1 ] && warn "$SHOW_DIR is on the Windows drive: slow through WSL. A directory under ~ is better."
    ;;
esac

mode=install
if [ -f "$DIR/.env" ]; then
  mode=update
elif [ -n "$(ls -A "$DIR" 2>/dev/null)" ] && [ ! -f "$DIR/compose.yaml" ] && [ ! -d "$DIR/data" ]; then
  die "$SHOW_DIR is not empty and holds no dev-box: run this again with an empty or new directory"
fi

# --- Shipped files: replaced only when the installed copy is still the one
# this script wrote (checksums in .setup-shipped). A copy edited by hand is
# never overwritten: the new version goes next to it as <file>.new ---
tmp="$DIR/.setup-tmp"
rm -rf "$tmp"
mkdir -p "$tmp/scripts"
trap 'rm -rf "$tmp"' EXIT

say "Downloading the files from $BASE_URL"
for f in $SHIPPED; do
  fetch "$f" "$tmp/$f" || die "cannot download $BASE_URL/$f, check the network"
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
  say "Existing install found in $SHOW_DIR: .env, compose.override.yaml and data/ are left as they are."
  image_in_env="$(env_get DEVBOX_IMAGE)"
  if [ -z "$image_in_env" ]; then
    die "DEVBOX_IMAGE is empty in $SHOW_DIR/.env, and this directory has no Dockerfile to build from.
  Set DEVBOX_IMAGE=$IMAGE in it, then run this again."
  fi
  if ! ask_yn "Pull the latest image ($image_in_env) and restart the box?" y; then
    say "Files refreshed, nothing else done. To update later:"
    say "  cd $SHOW_DIR"
    say "  docker compose pull && docker compose up -d"
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
  say "  logs:     cd $SHOW_DIR && docker compose logs -f"
  say "  in-box:   devbox update (dotfiles, tools, shipped config), devbox changelog"
  exit 0
fi

# --- New install: the questions ---
if [ -n "$(ls -A "$DIR/data/home" 2>/dev/null)" ]; then
  say ""
  say "$SHOW_DIR/data/home already holds a home, from an earlier install whose .env is gone."
  say "The new box will start on it, nothing in it is erased."
  if ! ask_yn "Continue with it?" y; then
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
      # shellcheck disable=SC2088 # shown as ~, read_keys expands it
      printf '%s' "~/.ssh/$k.pub"
      return
    fi
  done
}

# read_keys KEY|FILE|github:USER: the public keys, one per line, or an error.
read_keys() {
  case "$1" in
    github:*)
      gh_user="${1#github:}"
      printf '%s' "$gh_user" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$' || return 1
      keys="$(fetch_url "https://github.com/$gh_user.keys" 2>/dev/null || true)"
      ;;
    *)
      src="$(expand_home "$1")"
      if [ -f "$src" ]; then
        keys="$(grep -v '^[[:space:]]*\(#.*\)\{0,1\}$' "$src" || true)"
      else
        keys="$1"
      fi
      ;;
  esac
  [ -n "$keys" ] || return 1
  # every line a key type: ssh-ed25519, ssh-rsa, ecdsa-sha2-*, sk-*
  if printf '%s\n' "$keys" | grep -Evq '^(ssh-|ecdsa-|sk-)'; then return 1; fi
  printf '%s' "$keys"
}

say ""
say "A few questions. Enter keeps the value shown; everything can be changed later in $SHOW_DIR/.env."
say ""

# User
while :; do
  user="$(ask "Unix user inside the box" "$(example_get USER_NAME)")"
  printf '%s' "$user" | grep -q '^[a-z_][a-z0-9_-]*$' && break
  warn "invalid user name: $user (lowercase letters, digits, _ and -)"
done

# Timezone
tz="$(ask "Timezone" "$(host_tz)")"

# Access
say ""
say "How will you connect to the box?"
say "  tailscale: from any of your machines on your tailnet (Tailscale or Headscale account)"
say "  ssh:       an SSH port published on this host, public key only, no account needed"
access="$(ask_choice "Access" tailscale tailscale ssh)"

if [ "$access" = tailscale ]; then
  ts_hostname="$(ask "Tailscale hostname of the box" "$(example_get TS_HOSTNAME)")"
  ts_login_server="$(ask "Control server (your Headscale URL, or Tailscale)" "$(example_get TS_LOGIN_SERVER)")"
  say "An auth key attaches the box on its own; without one, a login URL is printed to open once."
  ts_authkey="$(ask_secret "Tailscale auth key")"
else
  # Two sources of keys, both asked every time: a GitHub account, then this
  # machine. Every key given is allowed in.
  say "Public keys allowed to log in: those of your GitHub account, then one of this machine."
  gh_keys=""
  while :; do
    gh_user="$(ask "GitHub user whose public keys are allowed in (empty to skip)" "")"
    gh_user="${gh_user#github:}"
    [ -n "$gh_user" ] || break
    if gh_keys="$(read_keys "github:$gh_user")"; then
      say "  $(printf '%s\n' "$gh_keys" | grep -c .) public key(s) taken from https://github.com/$gh_user.keys"
      break
    fi
    warn "no public key found at https://github.com/$gh_user.keys
  Check the user name, and that the account has an SSH key (GitHub, Settings, SSH and GPG keys)."
  done
  local_keys=""
  found="$(default_ssh_key_file)"
  [ -n "$found" ] || say "No public key in ~/.ssh on this machine (ssh-keygen -t ed25519 creates one)."
  while :; do
    if [ -n "$found" ]; then
      ssh_key="$(ask "Public key of this machine allowed in (a .pub file or the key itself)" "$found")"
    else
      ssh_key="$(ask "Public key of this machine allowed in (a .pub file or the key itself, empty to skip)" "")"
    fi
    [ -n "$ssh_key" ] || break
    local_keys="$(read_keys "$ssh_key")" && break
    warn "not a public key, nor a file of public keys: $ssh_key"
  done
  # More keys, as many as wanted: another machine, another GitHub account.
  more_keys=""
  while ask_yn "Add another key?" n; do
    while :; do
      ssh_key="$(ask "Key to add (a .pub file, the key itself, or github:<user>; empty to stop)" "")"
      [ -n "$ssh_key" ] || break
      if keys="$(read_keys "$ssh_key")"; then
        more_keys="$(printf '%s\n%s' "$more_keys" "$keys")"
        say "  $(printf '%s\n' "$keys" | grep -c .) public key(s) added"
        break
      fi
      case "$ssh_key" in
        github:*) warn "no public key found at https://github.com/${ssh_key#github:}.keys" ;;
        *) warn "not a public key, nor a file of public keys: $ssh_key" ;;
      esac
    done
  done
  # Every list together, each key once.
  ssh_keys="$(printf '%s\n%s\n%s\n' "$gh_keys" "$local_keys" "$more_keys" | awk 'NF && !seen[$0]++')"
  say "  $(printf '%s\n' "$ssh_keys" | grep -c .) public key(s) allowed in"
  if [ -z "$ssh_keys" ]; then
    warn "no public key: sshd will not start. Add one to SSH_AUTHORIZED_KEYS in .env later,
  or get in with docker exec -it -u $user $container zsh -l"
  fi
  while :; do
    ssh_port="$(ask "SSH port on this host" "$(example_get SSH_PORT)")"
    case "$ssh_port" in
      "" | *[!0-9]*) ;;
      *) [ "$ssh_port" -ge 1 ] && [ "$ssh_port" -le 65535 ] && break ;;
    esac
    warn "invalid SSH port: $ssh_port (a number from 1 to 65535)"
  done
  say "127.0.0.1: reachable from this machine only; 0.0.0.0: from the LAN too."
  ssh_bind="$(ask_choice "Address the SSH port listens on" "$(example_get SSH_BIND)" 127.0.0.1 0.0.0.0)"
fi

# Optional extras
say ""
say "A GitHub token with no scope avoids the GitHub API rate limit while tools install (recommended)."
github_token="$(ask_secret "GitHub token")"
say ""
say "Dev environments to install at the first start, space separated, empty for none."
say "For instance: node python php go rust java laravel network ansible (devbox dev-env --list in the box shows them all)."
dev_envs="$(ask "Dev environments" "")"
say ""
say "Rootless podman runs docker commands inside the box, but it loosens the isolation"
say "of the container (seccomp, /proc/sys and AppArmor opened)."
podman=no
ask_yn "Turn podman on?" n && podman=yes

# --- .env, written from .env.example ---
cp "$DIR/.env.example" "$DIR/.env.new"
env_set USER_NAME "$user"
env_set TZ "$tz"
env_set DEVBOX_IMAGE "$IMAGE"
if [ "$access" = tailscale ]; then
  env_set TS_DISABLE false
  env_set TS_HOSTNAME "$ts_hostname"
  env_set TS_LOGIN_SERVER "$ts_login_server"
  env_set TS_AUTHKEY "$ts_authkey"
else
  env_set TS_DISABLE true
  env_set SSH_AUTHORIZED_KEYS "$ssh_keys"
  env_set SSH_PORT "$ssh_port"
  env_set SSH_BIND "$ssh_bind"
fi
env_set GITHUB_TOKEN "$github_token"
env_set DEV_ENVS "$dev_envs"
if [ "$podman" = yes ]; then env_set PODMAN_ENABLE true; else env_set PODMAN_ENABLE false; fi
chmod 600 "$DIR/.env.new"
mv "$DIR/.env.new" "$DIR/.env"
say ""
say "Wrote $SHOW_DIR/.env"

if [ "$podman" = yes ]; then
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
    say "Wrote $SHOW_DIR/compose.override.yaml (the podman settings)"
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
docker compose config -q || die "docker compose rejects the configuration in $SHOW_DIR, see above"

# --- What to do next ---
next_steps() {
  say ""
  say "Connect:"
  if [ "$access" = tailscale ]; then
    say "  ssh $user@$ts_hostname          from any machine of your tailnet"
  else
    say "  ssh -p $ssh_port $user@127.0.0.1"
    [ "$ssh_bind" = 0.0.0.0 ] && say "  ssh -p $ssh_port $user@<this host's address>   from the LAN"
  fi
  say "  docker exec -it -u $user $container zsh -l   always works, on this host"
  say ""
  say "In $SHOW_DIR:"
  say "  docker compose logs -f                        what the box is doing"
  say "  docker compose pull && docker compose up -d   update to the latest image"
  say "  run the setup script again                     same, and refreshes compose.yaml"
  say "  edit .env, then docker compose up -d          change a setting"
  say "  docker compose down                           stop the box, data/ is kept"
  say "  scripts/backup.sh                             back up data/ (scripts/restore.sh to restore)"
  say ""
  say "Documentation: https://github.com/$REPO_SLUG/tree/main/docs"
  say ""
  say "Uninstall: cd $SHOW_DIR && docker compose down --rmi all, then delete $SHOW_DIR"
  say "  (that deletes your home and projects in data/; some files there belong to root: sudo rm -rf on Linux)"
}

say ""
if ! ask_yn "Pull the image and start the box now?" y; then
  say "Nothing started. To start it later:"
  say "  cd $SHOW_DIR"
  say "  docker compose pull && docker compose up -d"
  next_steps
  exit 0
fi

check_container_clash
say "Pulling $IMAGE (a few minutes the first time)"
docker compose pull
docker image inspect "$IMAGE" >/dev/null 2>&1 || die "the image $IMAGE is not there after the pull"
say "Starting the box"
docker compose up -d --no-build

if [ "$access" = tailscale ] && [ -z "$ts_authkey" ] && [ ! -s "$DIR/data/tailscale/tailscaled.state" ]; then
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
    say "  Not printed yet: follow docker compose logs -f in $SHOW_DIR, it shows the URL."
  fi
fi

say ""
say "The box is starting. The first start seeds your home, syncs the dotfiles and"
say "installs the tools in the background: a few minutes before everything is there."
next_steps
