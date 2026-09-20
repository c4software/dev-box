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
# appellent (zsh, tmux, LazyVim, gum, fzf, jq…) + le socle (tailscale, rsync…)
# + podman rootless (cf. /etc/containers/ et « Containers inside the box »).
# podman tire déjà passt, shadow, conmon et containers-common ; netavark tire
# aardvark-dns : seuls les paquets qu'aucun autre n'apporte sont listés ici.
RUN pacman -Syu --noconfirm --needed --disable-sandbox \
      base-devel git openssh sudo which less nano file lsof iptables python \
      tailscale zsh zsh-completions bash-completion tmux \
      rsync gum curl wget unzip \
      neovim luarocks tree-sitter-cli \
      starship zoxide fzf eza bat ripgrep fd lazygit jq \
      podman podman-docker docker-compose fuse-overlayfs crun netavark slirp4netns \
    # mise n'est pas dans les dépôts Arch Linux ARM : on retombe sur
    # l'installeur officiel, en posant le binaire dans le PATH de tout le monde
    # (et pas dans le ~/.local/bin de root).
    && if pacman -Si mise >/dev/null 2>&1; then \
         pacman -S --noconfirm --needed --disable-sandbox mise; \
       else \
         curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh; \
       fi \
    && mise --version \
    # Les images de base Arch perdent les capabilities de fichier (le tar qui
    # les produit ne garde pas les xattrs) : sans elles, podman rootless échoue
    # sur « newuidmap: Could not set caps ». On les repose explicitement.
    && setcap cap_setuid+ep /usr/bin/newuidmap \
    && setcap cap_setgid+ep /usr/bin/newgidmap \
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
    # podman-docker exporte DOCKER_HOST dans tous les shells de login, socket
    # ou pas : on ne le garde que si le socket existe (cf. /etc/devbox/zshenv).
    && rm -f /etc/profile.d/podman-docker.sh /etc/profile.d/podman-docker.csh \
    # docker et podman passent par un wrapper qui explique quoi faire quand
    # podman n'est pas activé (/usr/local/bin précède /usr/bin dans le PATH).
    && ln -s dev-box-podman /usr/local/bin/docker \
    && ln -s dev-box-podman /usr/local/bin/podman \
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
