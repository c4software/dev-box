# tmux automatique à l'arrivée en SSH (échappatoire : NO_TMUX=1)
# La session porte le nom de la machine (TS_HOSTNAME), tronqué au premier point :
# tmux refuse les points dans un nom de session.
# /etc/hostname plutôt que `hostname` : l'image Arch n'a pas ce binaire.
if [ -z "${TMUX:-}" ] && [ "${NO_TMUX:-}" != "1" ] \
   && [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}" ] \
   && command -v tmux >/dev/null 2>&1; then
  _devbox_session=$(cat /etc/hostname 2>/dev/null) || _devbox_session=""
  [ -n "$_devbox_session" ] || _devbox_session="${HOSTNAME:-}"
  _devbox_session=${_devbox_session%%.*}
  exec tmux new-session -A -s "${_devbox_session:-dev-box}" -c "$HOME"
fi
