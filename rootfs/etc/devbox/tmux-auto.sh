# Automatic tmux when you arrive over SSH (escape hatch: NO_TMUX=1)
# The session is named after the machine (TS_HOSTNAME), cut at the first dot:
# tmux refuses dots in a session name.
# /etc/hostname rather than `hostname`: the Arch image has no such binary.
if [ -z "${TMUX:-}" ] && [ "${NO_TMUX:-}" != "1" ] \
   && [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}" ] \
   && command -v tmux >/dev/null 2>&1; then
  _devbox_session=$(cat /etc/hostname 2>/dev/null) || _devbox_session=""
  [ -n "$_devbox_session" ] || _devbox_session="${HOSTNAME:-}"
  _devbox_session=${_devbox_session%%.*}
  exec tmux new-session -A -s "${_devbox_session:-dev-box}" -c "$HOME"
fi
