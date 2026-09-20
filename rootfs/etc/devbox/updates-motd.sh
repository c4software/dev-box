# dev-box : message de mise à jour au login (sourcé par les shells interactifs).
# Coût quand il n'y a rien : un seul test de fichier.
# Le drapeau est écrit par dev-box-check-updates (contrôle périodique).
if [ -f "$HOME/.cache/dev-box/updates" ]; then
  _devbox_motd=1
  # Dans tmux : une seule fois par session (et non par panneau)
  if [ -n "${TMUX:-}" ]; then
    if tmux show-environment DEVBOX_UPDATES_SHOWN >/dev/null 2>&1; then
      _devbox_motd=0
    else
      tmux set-environment DEVBOX_UPDATES_SHOWN 1 2>/dev/null || true
    fi
  fi
  if [ "$_devbox_motd" = 1 ]; then
    printf '\n\033[1;33mMises à jour disponibles\033[0m\n'
    sed 's/^/  /' "$HOME/.cache/dev-box/updates"
    printf '\033[2m→ dev-box-update\033[0m\n\n'
  fi
  unset _devbox_motd
fi
