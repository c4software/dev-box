# Variables du conteneur (écrites par l'entrypoint), pour les shells de login :
# /etc/bash.bashrc ne sert que les shells interactifs, et ni Tailscale SSH ni
# sshd n'héritent de l'environnement du PID 1.
[ -r /etc/devbox/env ] && . /etc/devbox/env
