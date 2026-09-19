FROM archlinux:latest

ENV LANG=C.UTF-8

# Paquets = ce que la conf de dotarchy/common-no-omarchy et ses scripts try/proj
# appellent (zsh, tmux, LazyVim, gum, fzf, jq…) + le socle (tailscale, rsync…).
RUN pacman -Syu --noconfirm --needed \
      base-devel git openssh sudo which less nano file lsof iptables python \
      tailscale zsh zsh-completions bash-completion tmux \
      rsync gum curl wget unzip \
      neovim luarocks tree-sitter-cli \
      mise starship zoxide fzf eza bat ripgrep fd lazygit jq \
    && pacman -Scc --noconfirm \
    && rm -rf /var/cache/pacman/pkg/*

COPY rootfs/ /
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/dotarchy-sync \
    && mkdir -p /etc/zsh \
    && cat /etc/devbox/zshenv >> /etc/zsh/zshenv \
    && echo '. /etc/devbox/tmux-auto.sh' >> /etc/zsh/zshrc \
    && cat /etc/devbox/bashrc >> /etc/bash.bashrc

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s \
  CMD [ "$TS_DISABLE" = "true" ] || tailscale status --peers=false >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
