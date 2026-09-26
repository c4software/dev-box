# shellcheck shell=bash
# devbox dev-env ansible: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Python + ansible-core + ansible-lint (mise)

Needs python, installed first. ansible-core (ansible, ansible-playbook,
ansible-galaxy, ansible-vault, ...) and ansible-lint are Python packages,
installed through mise, updated by `devbox update tools`. ansible-core comes
with the builtin modules only: the usual extras are one command away, kept in
~/.ansible/collections:
  ansible-galaxy collection install community.general
The box is the control node: the targets are other machines reached over SSH
(VMs, the lab, the tailnet), or containers of the box once podman is on
(community.docker or the podman connection). This checks the install:
  ansible localhost -m ping -c local
A removal takes out ansible-core and ansible-lint and leaves python,
~/.ansible (collections, roles) and the playbooks in place.
TXT
}

# Functions rather than arrays: a file runs nothing at the top level.
ansible_tools() { echo pypi:ansible-core pypi:ansible-lint; }

is_installed() { declared pypi:ansible-core; }

install() {
  local tools
  read -ra tools <<<"$(ansible_tools)"
  dev_env install python
  mise use -g "${tools[@]/%/@latest}"
  log "$(mise x pypi:ansible-core -- ansible --version | head -n 1)"
  log "ansible is ready: ansible localhost -m ping -c local, ansible-galaxy collection install community.general"
}

uninstall() {
  local tools
  read -ra tools <<<"$(ansible_tools)"
  unuse "${tools[@]}"
  log "python stays: devbox dev-env --remove python. ~/.ansible (collections, roles) is left in place."
}
