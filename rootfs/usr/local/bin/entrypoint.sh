#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${USER_NAME:-dev}"
# Fixed UID/GID: 1000:1000 (same owner as on the host for the volumes)
PUID=1000
PGID=1000
USER_SHELL="${USER_SHELL:-/bin/zsh}"
TS_HOSTNAME="${TS_HOSTNAME:-dev-box}"
HOME_DIR="/home/${USER_NAME}"
CHECK_INTERVAL="${UPDATE_CHECK_INTERVAL:-86400}"

log()     { echo "[dev-box] $*"; }
as_user() { su - "$USER_NAME" -w GITHUB_TOKEN,TZ -c "$1"; }

# --- 1. User (recreated at every start, the home is persistent) ---
if ! id "$USER_NAME" &>/dev/null; then
  groupadd -g "$PGID" "$USER_NAME"
  useradd -M -u "$PUID" -g "$PGID" -d "$HOME_DIR" -s "$USER_SHELL" "$USER_NAME"
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER_NAME"
  chmod 440 "/etc/sudoers.d/$USER_NAME"
fi
usermod -s "$USER_SHELL" "$USER_NAME"
# No password, but the account is not locked: useradd writes a "!", which sshd
# refuses even with key authentication.
usermod -p '*' "$USER_NAME"

# XDG_RUNTIME_DIR (used by the dotarchy zsh config: ssh-agent, rsync sockets)
install -d -m 700 -o "$PUID" -g "$PGID" "/run/user/$PUID"

# Delegated UID/GID ranges: without them, rootless podman refuses to start
# ("cannot find UID/GID for user").
for f in /etc/subuid /etc/subgid; do
  grep -q "^${USER_NAME}:" "$f" 2>/dev/null || echo "${USER_NAME}:100000:65536" >> "$f"
done

# dotarchy-sync settings, read as well when it is run by hand
{
  printf 'DOTARCHY_REPO=%q\n'   "${DOTARCHY_REPO:-https://github.com/c4software/dotarchy.git}"
  printf 'DOTARCHY_BRANCH=%q\n' "${DOTARCHY_BRANCH:-main}"
  printf 'DOTARCHY_SUBDIR=%q\n' "${DOTARCHY_SUBDIR:-common-no-omarchy}"
} > /etc/devbox/dotarchy.env

# Variables to find again in login shells (see /etc/devbox/zshenv)
{
  for v in TZ GITHUB_TOKEN LLM_PROXY_URL LLM_PROXY_API_KEY; do
    [ -n "${!v:-}" ] && printf 'export %s=%q\n' "$v" "${!v}" || true
  done
  # Access mode, read by dev-box-status (an SSH session does not see the env of PID 1)
  printf 'export TS_DISABLE=%q\n' "${TS_DISABLE:-false}"
  # Environments asked for at start, shown by dev-box-status
  printf 'export DEV_ENVS=%q\n' "${DEV_ENVS:-}"
} > /etc/devbox/env
chown "$PUID:$PGID" /etc/devbox/env
chmod 600 /etc/devbox/env

# --- 2. First start: setting up the home ---
mkdir -p "$HOME_DIR"
FIRST_BOOT=false
if [ ! -f "$HOME_DIR/.dev-box-init" ]; then
  FIRST_BOOT=true
  log "Setting up $HOME_DIR"
  cp -r --update=none /etc/skel/. "$HOME_DIR/"
  mkdir -p "$HOME_DIR/.config/mise" "$HOME_DIR/.local/bin" "$HOME_DIR/projets"
  touch "$HOME_DIR/.dev-box-init"
  # chown the home without descending into ~/projets (a separate volume, existing content untouched)
  find "$HOME_DIR" -path "$HOME_DIR/projets" -prune -o -exec chown -h "$PUID:$PGID" {} +
fi
# ~/projets is a separate volume: Docker creates the source as root when it does not exist
mkdir -p "$HOME_DIR/projets"
if [ "$(stat -c %u "$HOME_DIR/projets")" != "$PUID" ]; then
  chown "$PUID:$PGID" "$HOME_DIR/projets"
fi

# A temporary ~/.zshrc until the first sync
if [ ! -f "$HOME_DIR/.zshrc" ]; then
  cp /etc/devbox/zshrc "$HOME_DIR/.zshrc"
  chown "$PUID:$PGID" "$HOME_DIR/.zshrc"
fi

# Config shipped by the image (agents, extensions, mise config): laid down when
# missing, updated when the user never touched it, never overwritten otherwise.
DEVBOX_HOME="$HOME_DIR" dev-box-seed || log "⚠ dev-box-seed failed"

# The "devbox" skill for the coding agents (claude, pi, omp): a link to the
# image rather than a copy, so it follows the rebuilds without going through
# the seed. claude reads ~/.claude/skills, pi and omp read <config dir>/agent/skills.
for skills_dir in "$HOME_DIR/.claude/skills" \
                  "$HOME_DIR/.pi/agent/skills" \
                  "$HOME_DIR/.omp/agent/skills"; do
  mkdir -p "$skills_dir"
  # mkdir -p as root would leave directories the user cannot reach, so we walk
  # the whole chain back up to the home.
  sub="$skills_dir"
  while [ "$sub" != "$HOME_DIR" ] && [ "$sub" != "/" ]; do
    chown "$PUID:$PGID" "$sub"
    sub="$(dirname "$sub")"
  done
  ln -sfn /usr/share/devbox/skills/devbox "$skills_dir/devbox"
  chown -h "$PUID:$PGID" "$skills_dir/devbox"
done

# Migrations shipped by the image: the one thing the start does on its own. A
# new image can change something the seed cannot pick up alone, and the
# migration that comes with it repairs that once and for all.
# A new home has nothing to repair: everything is acknowledged, nothing is run.
if [ "$FIRST_BOOT" = "true" ]; then
  as_user "dev-box-migrate --mark-all-done" || log "⚠ dev-box-migrate failed"
  # The first interactive login proposes the guided tour (dev-box-tour --offer)
  as_user "mkdir -p ~/.config/dev-box && touch ~/.config/dev-box/tour-pending" \
    || log "⚠ could not flag the tour"
  # Nothing changed for a new home: the changelog starts from this image
  as_user "dev-box-changelog --mark-seen" || log "⚠ could not mark the changelog as seen"
else
  as_user "dev-box-migrate" || log "⚠ a migration failed (devbox migrate to try again)"
fi

# pacman packages kept by dev-box-pkg: the image is disposable, so after a
# rebuild they are gone. Reinstalled in the background, without holding up access.
PKG_LIST="$HOME_DIR/.config/dev-box/packages"
if [ -s "$PKG_LIST" ]; then
  (
    missing=()
    while IFS= read -r pkg; do
      case "$pkg" in ''|'#'*) continue ;; esac
      pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done < "$PKG_LIST"
    if [ "${#missing[@]}" -gt 0 ]; then
      # The pacman database of the image dates from the build: when it is too
      # old for the mirrors the download fails, and a -Sy brings it up to date.
      if pacman -S --needed --noconfirm "${missing[@]}" >> /tmp/dev-box-pkg.log 2>&1 ||
         { pacman -Sy --noconfirm >> /tmp/dev-box-pkg.log 2>&1 &&
           pacman -S --needed --noconfirm "${missing[@]}" >> /tmp/dev-box-pkg.log 2>&1; }; then
        log "pkg: ${#missing[@]} package(s) reinstalled"
      else
        log "⚠ pkg: could not reinstall, see /tmp/dev-box-pkg.log"
      fi
    fi
  ) &
fi

# --- 3. Docker-compatible podman socket (DOCKER_HOST of the shells), opt-in ---
# Started as the user, rootless: `docker run`, `docker build` and
# `docker compose` inside the box go through it, with no host Docker socket.
# It needs /dev/fuse and the security_opt of compose.override.example.yaml.
# A failure is reported but does not stop the box from starting.
# The state is read by the dev-box-podman wrapper (a clear message when off)
if [ "${PODMAN_ENABLE:-false}" = "true" ]; then echo enabled; else echo disabled; fi > /etc/devbox/podman.state
chmod 644 /etc/devbox/podman.state
if [ "${PODMAN_ENABLE:-false}" = "true" ]; then
  PODMAN_SOCK="/run/user/$PUID/podman/podman.sock"
  install -d -m 700 -o "$PUID" -g "$PGID" "/run/user/$PUID/podman"
  rm -f "$PODMAN_SOCK"
  as_user "mkdir -p ~/.cache && XDG_RUNTIME_DIR=/run/user/$PUID \
           exec /usr/bin/podman system service --time=0 unix://$PODMAN_SOCK \
           >> ~/.cache/dev-box-podman.log 2>&1" &
  (
    for _ in $(seq 1 50); do
      if [ -S "$PODMAN_SOCK" ]; then
        log "podman: socket ready on $PODMAN_SOCK"
        exit 0
      fi
      sleep 0.2
    done
    log "⚠ podman: no socket, see ~/.cache/dev-box-podman.log"
  ) &
fi

# --- 4. First start: dotfiles + tools. Every start: the missing mise tools,
#        the dev environments of DEV_ENVS, then the update check only
#        (everything is updated by hand with `dev-box-update`).
#        In the background, before Tailscale: `tailscale up` can wait for an
#        interactive login when TS_AUTHKEY is empty. ---
(
  if [ "$FIRST_BOOT" = "true" ]; then
    as_user "dotarchy-sync" || log "⚠ dotarchy-sync failed"
  fi
  # MISE_INSTALL_ON_START reinstalls what is missing, without bumping a version
  if [ "$FIRST_BOOT" = "true" ] || [ "${MISE_INSTALL_ON_START:-true}" = "true" ]; then
    if as_user "mkdir -p ~/.cache && { mise install node && mise install; } \
                >> ~/.cache/dev-box-install.log 2>&1"; then
      log "mise: tools installed"
    else
      log "⚠ mise install failed, see ~/.cache/dev-box-install.log"
    fi
  fi
  # DEV_ENVS: the dev environments every start makes sure are there, through
  # `dev-box-dev-env --if-missing`. What is installed already is skipped, so
  # this only costs something after a fresh home or a new name in .env. The
  # flag ~/.cache/dev-box/dev-envs says what is going on (printed at login and
  # by dev-box-status): "installing" while it runs, the error when it failed,
  # gone when everything is there. The full output is in dev-envs.log.
  if [ -n "${DEV_ENVS:-}" ]; then
    DEV_ENVS_FLAG="$HOME_DIR/.cache/dev-box/dev-envs"
    DEV_ENVS_LOG="$HOME_DIR/.cache/dev-box/dev-envs.log"
    as_user "mkdir -p ~/.cache/dev-box"
    printf 'DEV_ENVS: installing %s (started at boot, ~/.cache/dev-box/dev-envs.log)\n' "$DEV_ENVS" > "$DEV_ENVS_FLAG"
    chown "$PUID:$PGID" "$DEV_ENVS_FLAG"
    # The browser environment goes through pacman, and so does the package
    # restore above: wait for its lock rather than fail on it.
    for _ in $(seq 1 300); do
      [ -e /var/lib/pacman/db.lck ] || break
      sleep 1
    done
    if as_user "dev-box-dev-env --if-missing $DEV_ENVS > ~/.cache/dev-box/dev-envs.log 2>&1"; then
      log "dev-envs: $DEV_ENVS ready"
      rm -f "$DEV_ENVS_FLAG"
    else
      # One line for the login message: the reason when the script gave one
      # (an unknown name, a failed environment), the log otherwise.
      reason="$(grep -m1 -E 'unknown environment|failed' "$DEV_ENVS_LOG" \
                | sed 's/\x1b\[[0-9;]*m//g; s/^dev-box-dev-env: //; s/^\[dev-box-dev-env\] //' || true)"
      printf 'DEV_ENVS: %s (DEV_ENVS in .env, ~/.cache/dev-box/dev-envs.log)\n' "${reason:-install failed}" > "$DEV_ENVS_FLAG"
      chown "$PUID:$PGID" "$DEV_ENVS_FLAG"
      log "⚠ dev-envs: ${reason:-install failed}, see ~/.cache/dev-box/dev-envs.log"
    fi
  else
    rm -f "$HOME_DIR/.cache/dev-box/dev-envs"
  fi
  # Periodic check: writes ~/.cache/dev-box/updates, printed at login
  if [ "$CHECK_INTERVAL" -gt 0 ] 2>/dev/null; then
    as_user "dev-box-check-updates --quiet" >/dev/null 2>&1 || log "⚠ could not run the update check"
    while sleep "$CHECK_INTERVAL"; do
      as_user "dev-box-check-updates --quiet" >/dev/null 2>&1 || log "⚠ could not run the update check"
    done
  fi
) &

# --- 5. Access: Tailscale SSH, or OpenSSH on the published port when TS_DISABLE=true ---
if [ "${TS_DISABLE:-false}" = "true" ]; then
  log "Tailscale is off (TS_DISABLE=true): starting OpenSSH"

  # StrictModes: sshd refuses the authentication when the home is writable by
  # the group or by everyone (common on a bind mount created by hand).
  if [ -n "$(find "$HOME_DIR" -maxdepth 0 -perm /022)" ]; then
    chmod go-w "$HOME_DIR"
    log "$HOME_DIR made non-writable by group and others (StrictModes)"
  fi

  # Host keys in the persistent home: no "host key changed" after a rebuild or
  # a recreation of the container.
  KEY_DIR="$HOME_DIR/.config/dev-box/ssh"
  install -d -m 700 -o "$PUID" -g "$PGID" "$KEY_DIR"
  for t in ed25519 rsa; do
    [ -f "$KEY_DIR/ssh_host_${t}_key" ] && continue
    ssh-keygen -q -t "$t" -N '' -f "$KEY_DIR/ssh_host_${t}_key"
    log "$t host key generated"
  done
  chown -R "$PUID:$PGID" "$KEY_DIR"
  chmod 600 "$KEY_DIR"/ssh_host_*_key

  AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"
  if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
    install -d -m 700 -o "$PUID" -g "$PGID" "$HOME_DIR/.ssh"
    printf '%s\n' "$SSH_AUTHORIZED_KEYS" > "$AUTH_KEYS"
    chown "$PUID:$PGID" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
  fi
  if [ ! -s "$AUTH_KEYS" ]; then
    log "⚠ no public key: set SSH_AUTHORIZED_KEYS in .env"
    log "  fallback access: docker exec -it -u $USER_NAME dev-box zsh -l"
    exec sleep infinity
  fi

  log "sshd: ssh -p <published port> ${USER_NAME}@<host>"
  exec /usr/bin/sshd -D -e -f /etc/devbox/sshd_config \
       -o "AllowUsers=$USER_NAME" \
       -h "$KEY_DIR/ssh_host_ed25519_key" -h "$KEY_DIR/ssh_host_rsa_key"
fi

mkdir -p /var/lib/tailscale /var/run/tailscale
tailscaled --state=/var/lib/tailscale/tailscaled.state \
           --socket=/var/run/tailscale/tailscaled.sock &
TSD_PID=$!
for _ in $(seq 1 50); do
  [ -S /var/run/tailscale/tailscaled.sock ] && break
  sleep 0.2
done

# --operator lets the user drive tailscale serve without sudo. --reset is
# already there, so the prefs are re-applied at every start.
up_args=(--hostname="$TS_HOSTNAME" --ssh --reset --operator="$USER_NAME")
if [ -n "${TS_LOGIN_SERVER:-}" ]; then up_args+=(--login-server="$TS_LOGIN_SERVER"); fi
if [ -n "${TS_AUTHKEY:-}" ];      then up_args+=(--authkey="$TS_AUTHKEY"); fi
# shellcheck disable=SC2206
if [ -n "${TS_EXTRA_ARGS:-}" ];   then up_args+=($TS_EXTRA_ARGS); fi
tailscale up "${up_args[@]}"
log "Tailscale OK: ssh ${USER_NAME}@${TS_HOSTNAME}"

wait "$TSD_PID"
