#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${USER_NAME:-dev}"
# UID/GID fixes : 1000:1000 (même propriétaire que sur l'hôte pour les volumes)
PUID=1000
PGID=1000
USER_SHELL="${USER_SHELL:-/bin/zsh}"
TS_HOSTNAME="${TS_HOSTNAME:-devbox}"
HOME_DIR="/home/${USER_NAME}"
SYNC_INTERVAL="${DOTARCHY_SYNC_INTERVAL:-3600}"

log()     { echo "[dev-box] $*"; }
as_user() { su - "$USER_NAME" -w GITHUB_TOKEN,TZ -c "$1"; }

# --- 1. Utilisateur (recréé à chaque démarrage, le home est persistant) ---
if ! id "$USER_NAME" &>/dev/null; then
  groupadd -g "$PGID" "$USER_NAME"
  useradd -M -u "$PUID" -g "$PGID" -d "$HOME_DIR" -s "$USER_SHELL" "$USER_NAME"
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER_NAME"
  chmod 440 "/etc/sudoers.d/$USER_NAME"
fi
usermod -s "$USER_SHELL" "$USER_NAME"

# XDG_RUNTIME_DIR (utilisé par la conf zsh de dotarchy : ssh-agent, sockets rsync)
install -d -m 700 -o "$PUID" -g "$PGID" "/run/user/$PUID"

# Réglages dotarchy-sync, lus aussi quand on le lance à la main
{
  printf 'DOTARCHY_REPO=%q\n'   "${DOTARCHY_REPO:-https://github.com/c4software/dotarchy.git}"
  printf 'DOTARCHY_BRANCH=%q\n' "${DOTARCHY_BRANCH:-main}"
  printf 'DOTARCHY_SUBDIR=%q\n' "${DOTARCHY_SUBDIR:-common-no-omarchy}"
} > /etc/devbox/dotarchy.env

# --- 2. Premier démarrage : initialisation du home ---
mkdir -p "$HOME_DIR"
if [ ! -f "$HOME_DIR/.dev-box-init" ]; then
  log "Initialisation de $HOME_DIR"
  cp -r --update=none /etc/skel/. "$HOME_DIR/"
  mkdir -p "$HOME_DIR/.config/mise" "$HOME_DIR/.local/bin" "$HOME_DIR/projets"
  cp --update=none /etc/devbox/mise-config.toml "$HOME_DIR/.config/mise/config.toml"
  touch "$HOME_DIR/.dev-box-init"
  # chown du home sans descendre dans ~/projets (volume à part, contenu existant intact)
  find "$HOME_DIR" -path "$HOME_DIR/projets" -prune -o -exec chown -h "$PUID:$PGID" {} +
fi
# ~/projets est un volume à part : Docker crée la source en root si elle n'existe pas
mkdir -p "$HOME_DIR/projets"
if [ "$(stat -c %u "$HOME_DIR/projets")" != "$PUID" ]; then
  chown "$PUID:$PGID" "$HOME_DIR/projets"
fi

# ~/.zshrc provisoire en attendant la première synchronisation
if [ ! -f "$HOME_DIR/.zshrc" ]; then
  cp /etc/devbox/zshrc "$HOME_DIR/.zshrc"
  chown "$PUID:$PGID" "$HOME_DIR/.zshrc"
fi

# --- 3. Dotfiles + outils (en arrière-plan, avant Tailscale : `tailscale up` peut
#        attendre un login interactif si TS_AUTHKEY est vide) ---
(
  as_user "dotarchy-sync" || log "⚠ dotarchy-sync a échoué"
  if [ "${MISE_INSTALL_ON_START:-true}" = "true" ]; then
    if as_user "mkdir -p ~/.cache && { mise install node && mise install; } \
                >> ~/.cache/dev-box-install.log 2>&1"; then
      log "mise : outils à jour"
    else
      log "⚠ mise install a échoué, voir ~/.cache/dev-box-install.log"
    fi
  fi
  # Resynchronisation périodique des dotfiles (0 = désactivé)
  if [ "$SYNC_INTERVAL" -gt 0 ] 2>/dev/null; then
    while sleep "$SYNC_INTERVAL"; do
      as_user "dotarchy-sync" >/dev/null || log "⚠ dotarchy-sync périodique a échoué"
    done
  fi
) &

# --- 4. Tailscale (dans ce conteneur : Tailscale SSH ouvre le shell ici) ---
# TS_DISABLE=true : debug sans Tailscale, on entre avec `docker exec`
if [ "${TS_DISABLE:-false}" = "true" ]; then
  log "Tailscale désactivé (TS_DISABLE=true) : docker exec -it -u $USER_NAME dev-box zsh -l"
  exec sleep infinity
fi

mkdir -p /var/lib/tailscale /var/run/tailscale
tailscaled --state=/var/lib/tailscale/tailscaled.state \
           --socket=/var/run/tailscale/tailscaled.sock &
TSD_PID=$!
for _ in $(seq 1 50); do
  [ -S /var/run/tailscale/tailscaled.sock ] && break
  sleep 0.2
done

up_args=(--hostname="$TS_HOSTNAME" --ssh --reset)
if [ -n "${TS_LOGIN_SERVER:-}" ]; then up_args+=(--login-server="$TS_LOGIN_SERVER"); fi
if [ -n "${TS_AUTHKEY:-}" ];      then up_args+=(--authkey="$TS_AUTHKEY"); fi
# shellcheck disable=SC2206
if [ -n "${TS_EXTRA_ARGS:-}" ];   then up_args+=($TS_EXTRA_ARGS); fi
tailscale up "${up_args[@]}"
log "Tailscale OK : ssh ${USER_NAME}@${TS_HOSTNAME}"

wait "$TSD_PID"
