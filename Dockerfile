# syntax=docker/dockerfile:1

# Image de base selon l'architecture (BuildKit fournit TARGETARCH) :
#   - amd64 : l'image officielle archlinux, qui n'existe qu'en x86_64 ;
#   - arm64 : Arch Linux ARM via l'image communautaire menci/archlinuxarm,
#     reconstruite chaque jour (Raspberry Pi 5).
FROM archlinux:latest AS base-amd64
FROM menci/archlinuxarm:base AS base-arm64

# Déclaré avant le FROM final pour pouvoir servir dans son nom d'étape.
ARG TARGETARCH
FROM base-${TARGETARCH}

ENV LANG=C.UTF-8

# --disable-sandbox : pacman 7 isole ses téléchargements avec Landlock, absent
# des noyaux qui ne l'activent pas et de l'émulation qemu (build arm64 croisé) ;
# sans ce drapeau, le `-Sy` échoue avant même de télécharger quoi que ce soit.
#
# Paquets = ce que la conf de dotarchy/common-no-omarchy et ses scripts try/proj
# appellent (zsh, tmux, LazyVim, gum, fzf, jq…) + le socle (tailscale, rsync…).
RUN pacman -Syu --noconfirm --needed --disable-sandbox \
      base-devel git openssh sudo which less nano file lsof iptables python \
      tailscale zsh zsh-completions bash-completion tmux \
      rsync gum curl wget unzip \
      neovim luarocks tree-sitter-cli \
      starship zoxide fzf eza bat ripgrep fd lazygit jq \
    # mise n'est pas dans les dépôts Arch Linux ARM : on retombe sur
    # l'installeur officiel, en posant le binaire dans le PATH de tout le monde
    # (et pas dans le ~/.local/bin de root).
    && if pacman -Si mise >/dev/null 2>&1; then \
         pacman -S --noconfirm --needed --disable-sandbox mise; \
       else \
         curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh; \
       fi \
    && mise --version \
    && pacman -Scc --noconfirm --disable-sandbox \
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
