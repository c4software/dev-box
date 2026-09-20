# Container variables (written by the entrypoint), for login shells:
# /etc/bash.bashrc only serves interactive shells, and neither Tailscale SSH
# nor sshd inherits the environment of PID 1.
[ -r /etc/devbox/env ] && . /etc/devbox/env
