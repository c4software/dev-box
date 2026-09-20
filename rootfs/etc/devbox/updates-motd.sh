# dev-box: update message at login (sourced by interactive shells).
# When there is nothing, the cost is a single file test.
# The flag is written by dev-box-check-updates (the periodic check).
if [ -f "$HOME/.cache/dev-box/updates" ]; then
  _devbox_motd=1
  # Inside tmux: once per session, not once per pane
  if [ -n "${TMUX:-}" ]; then
    if tmux show-environment DEVBOX_UPDATES_SHOWN >/dev/null 2>&1; then
      _devbox_motd=0
    else
      tmux set-environment DEVBOX_UPDATES_SHOWN 1 2>/dev/null || true
    fi
  fi
  if [ "$_devbox_motd" = 1 ]; then
    printf '\n\033[1;33mUpdates available\033[0m\n'
    sed 's/^/  /' "$HOME/.cache/dev-box/updates"
    printf '\033[2mRun: devbox update\033[0m\n\n'
  fi
  unset _devbox_motd
fi
