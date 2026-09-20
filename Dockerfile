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
# Commit du dépôt dev-box dont l'image est issue (build args, posés par le
# justfile) : dev-box-check-updates le compare au dépôt distant.
ARG DEVBOX_COMMIT=unknown
ARG DEVBOX_REPO=
ARG DEVBOX_BRANCH=main
RUN printf 'DEVBOX_COMMIT=%s\nDEVBOX_REPO=%s\nDEVBOX_BRANCH=%s\n' \
      "$DEVBOX_COMMIT" "$DEVBOX_REPO" "$DEVBOX_BRANCH" > /etc/devbox/release \
    && chmod +x /usr/local/bin/* \
    && mkdir -p /etc/zsh \
    && cat /etc/devbox/zshenv >> /etc/zsh/zshenv \
    && echo '. /etc/devbox/tmux-auto.sh' >> /etc/zsh/zshrc \
    && echo '. /etc/devbox/updates-motd.sh' >> /etc/zsh/zshrc \
    && cat /etc/devbox/bashrc >> /etc/bash.bashrc

# Sain quand Tailscale est connecté, ou quand sshd écoute (TS_DISABLE=true).
HEALTHCHECK --interval=60s --timeout=5s --start-period=30s \
  CMD if [ "$TS_DISABLE" = "true" ]; then \
        bash -c '</dev/tcp/127.0.0.1/22' 2>/dev/null || exit 1; \
      else \
        tailscale status --peers=false >/dev/null || exit 1; \
      fi

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
