# dev-box: the login message (sourced by interactive shells).
# The message itself is dev-box-motd: it reads nothing but the box, never the
# network, so what happens here is a guard and one call. Inside tmux it is
# printed once per session, not once per pane; elsewhere, once per shell.
# The file keeps its name: the Dockerfile and /etc/devbox/bashrc source it.
if command -v dev-box-motd >/dev/null 2>&1; then
  _devbox_motd=1
  if [ -n "${TMUX:-}" ]; then
    if tmux show-environment DEVBOX_MOTD_SHOWN >/dev/null 2>&1; then
      _devbox_motd=0
    else
      tmux set-environment DEVBOX_MOTD_SHOWN 1 2>/dev/null || true
    fi
  fi
  if [ "$_devbox_motd" = 1 ]; then
    dev-box-motd 2>/dev/null || true
    # First login: the guided tour is proposed once, when the flag is there.
    if [ -f "$HOME/.config/dev-box/tour-pending" ] && command -v dev-box-tour >/dev/null 2>&1; then
      dev-box-tour --offer || true
    fi
  fi
  unset _devbox_motd
fi
