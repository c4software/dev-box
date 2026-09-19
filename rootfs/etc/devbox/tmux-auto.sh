# tmux automatique à l'arrivée en SSH (échappatoire : NO_TMUX=1)
# Session « dev-box », du nom du projet.
if [ -z "${TMUX:-}" ] && [ "${NO_TMUX:-}" != "1" ] \
   && [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}" ] \
   && command -v tmux >/dev/null 2>&1; then
  exec tmux new-session -A -s dev-box -c "$HOME"
fi
