# syntax=docker/dockerfile:1

# Base image per architecture (BuildKit provides TARGETARCH):
#   - amd64: the official archlinux image, which only exists for x86_64;
#   - arm64: Arch Linux ARM through the community image menci/archlinuxarm,
#     rebuilt every day (Raspberry Pi 5).
FROM archlinux:latest AS base-amd64
FROM menci/archlinuxarm:base AS base-arm64

# Declared before the final FROM so it can be used in its stage name.
ARG TARGETARCH
FROM base-${TARGETARCH}

ENV LANG=C.UTF-8

# --disable-sandbox: pacman 7 isolates its downloads with Landlock, which is
# missing from kernels that do not enable it and from qemu emulation (a cross
# arm64 build); without that flag the `-Sy` fails before downloading anything.
#
# Packages = what the dotarchy/common-no-omarchy config and its try/proj scripts
# call (zsh, tmux, LazyVim, gum, fzf, jq, ...) + the base (tailscale, rsync, ...)
# + rootless podman (see /etc/containers/ and docs/containers.md)
# + libyaml, which the precompiled ruby laid down by dev-box-dev-env needs (psych)
# + php, composer, php-sqlite, php-gd, php-sodium, xdebug: mise can only build PHP
#   (5 to 15 minutes and a pile of headers), so PHP is the one dev-box-dev-env
#   environment that comes from the image, as it does in omarchy.
# + github-cli: gh, as on an omarchy machine (PRs, issues, workflow runs from the box).
# + yazi: the file manager `open <directory>` (the xdg-open shim) opens in a tmux pane.
# + chafa, 7zip, resvg, imagemagick, poppler: what yazi previews with. Images
#   are drawn by the terminal itself (Kitty graphics, Sixel, iTerm2), through
#   tmux and SSH; chafa is the text fallback for a terminal that has none.
#   7zip lists archives, resvg renders SVG, imagemagick handles HEIC, AVIF and
#   fonts, poppler (pdftoppm) the PDF pages. ffmpeg (video thumbnails) is left
#   out on purpose: 50 MB and a pile of audio libraries, `devbox dev-env
#   media` for the boxes that want it.
# + sqlite: the sqlite3 shell. Already pulled by python and php-sqlite, listed
#   so that it stays whatever those dependencies do.
# + postgresql-libs (psql, pg_dump) and mariadb-clients (mariadb, mysql,
#   mariadb-dump): the clients of the servers `devbox dbs` starts, so that
#   `psql -h 127.0.0.1 -U postgres` (docs/databases.md) and
#   `mysql -h 127.0.0.1 -u root` work from the box without a dev-env.
# + bind (dig, nslookup, host), openbsd-netcat (nc), whois, traceroute: the
#   network basics a SISR student reaches for first; about 9 MB together, the
#   rest of their dependencies is already there. The heavier tools (nmap,
#   tcpdump, iperf3, ...) are `devbox dev-env network`.
# podman already pulls passt, shadow, conmon and containers-common, and netavark
# pulls aardvark-dns: only the packages no other one brings are listed here.
RUN pacman -Syu --noconfirm --needed --disable-sandbox \
      base-devel git openssh sudo which less nano file lsof iptables python \
      tailscale zsh zsh-completions bash-completion tmux \
      rsync gum curl wget unzip github-cli yazi chafa 7zip resvg imagemagick poppler \
      neovim luarocks tree-sitter-cli \
      starship zoxide fzf eza bat ripgrep fd lazygit jq \
      libyaml sqlite postgresql-libs mariadb-clients \
      bind openbsd-netcat whois traceroute \
      php composer php-sqlite php-gd php-sodium xdebug \
      podman podman-docker docker-compose fuse-overlayfs crun netavark slirp4netns \
    # mise is not in the Arch Linux ARM repositories: we fall back on the
    # official installer, and put the binary on everyone's PATH (rather than in
    # root's ~/.local/bin).
    && if pacman -Si mise >/dev/null 2>&1; then \
         pacman -S --noconfirm --needed --disable-sandbox mise; \
       else \
         curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh; \
       fi \
    && mise --version \
    # The Arch base images lose their file capabilities (the tar that produces
    # them does not keep the xattrs): without them, rootless podman fails on
    # "newuidmap: Could not set caps". We set them again explicitly.
    # PHP ready for development: the usual extensions and xdebug enabled
    # (omarchy does the same in omarchy-install-dev-env, here it is baked into
    # the image).
    && sed -i -E 's/^;(extension=(bcmath|intl|iconv|openssl|pdo_sqlite|pdo_mysql|sqlite3|mysqli|zip|gd|sodium))$/\1/' /etc/php/php.ini \
    && sed -i -e 's/^;zend_extension=xdebug.so/zend_extension=xdebug.so/' \
              -e 's/^;xdebug.mode=debug/xdebug.mode=debug/' /etc/php/conf.d/xdebug.ini \
    && setcap cap_setuid+ep /usr/bin/newuidmap \
    && setcap cap_setgid+ep /usr/bin/newgidmap \
    && pacman -Scc --noconfirm --disable-sandbox \
    && rm -rf /var/cache/pacman/pkg/*

COPY rootfs/ /
# Commit of the dev-box repo the image was built from: dev-box-check-updates
# compares it with the remote repo. The build args are empty by default
# (compose.yaml passes them from the environment, the GitHub workflow sets
# them) and the build then reads the clone it runs from instead: commit,
# origin, branch and git describe (the context is mounted read-only, nothing
# is copied into the image). A context with no .git (a tarball) records
# "unknown".
ARG DEVBOX_COMMIT=
ARG DEVBOX_REPO=
ARG DEVBOX_BRANCH=
# The release tag (v1.5), and "release" for the image the workflow publishes:
# the box then compares itself with the newest v* tag of the repo rather than
# the head of the branch. A local build records git describe and "local".
ARG DEVBOX_VERSION=
ARG DEVBOX_SOURCE=local
RUN --mount=type=bind,target=/ctx,ro \
    commit="$DEVBOX_COMMIT"; repo="$DEVBOX_REPO"; branch="$DEVBOX_BRANCH"; version="$DEVBOX_VERSION"; \
    if [ -e /ctx/.git ]; then \
      # the clone belongs to the host user, not root: git refuses it otherwise
      g="git -c safe.directory=/ctx -C /ctx"; \
      [ -n "$commit" ] && [ "$commit" != unknown ] || commit="$($g rev-parse HEAD 2>/dev/null || echo unknown)"; \
      [ -n "$repo" ] || repo="$($g remote get-url origin 2>/dev/null || true)"; \
      [ -n "$branch" ] || branch="$($g rev-parse --abbrev-ref HEAD 2>/dev/null || true)"; \
      [ -n "$version" ] || version="$($g describe --tags --always 2>/dev/null || true)"; \
    fi; \
    [ -n "$commit" ] || commit=unknown; \
    [ -n "$branch" ] && [ "$branch" != HEAD ] || branch=main; \
    printf 'DEVBOX_COMMIT=%s\nDEVBOX_REPO=%s\nDEVBOX_BRANCH=%s\nDEVBOX_VERSION=%s\nDEVBOX_SOURCE=%s\n' \
      "$commit" "$repo" "$branch" "$version" "${DEVBOX_SOURCE:-local}" > /etc/devbox/release \
    && echo "release: $version $commit $repo ($branch, ${DEVBOX_SOURCE:-local})" \
    && chmod +x /usr/local/bin/* \
    # podman-docker exports DOCKER_HOST in every login shell, socket or not:
    # we keep it only when the socket exists (see /etc/devbox/zshenv).
    && rm -f /etc/profile.d/podman-docker.sh /etc/profile.d/podman-docker.csh \
    # docker and podman go through a wrapper that says what to do when podman
    # is not enabled (/usr/local/bin comes before /usr/bin on the PATH).
    && ln -s dev-box-podman /usr/local/bin/docker \
    && ln -s dev-box-podman /usr/local/bin/podman \
    && mkdir -p /etc/zsh \
    && cat /etc/devbox/zshenv >> /etc/zsh/zshenv \
    && echo '. /etc/devbox/tmux-auto.sh' >> /etc/zsh/zshrc \
    && echo '. /etc/devbox/updates-motd.sh' >> /etc/zsh/zshrc \
    && cat /etc/devbox/bashrc >> /etc/bash.bashrc

# Healthy when Tailscale is connected, or when sshd listens (TS_DISABLE=true).
HEALTHCHECK --interval=60s --timeout=5s --start-period=30s \
  CMD if [ "$TS_DISABLE" = "true" ]; then \
        bash -c '</dev/tcp/127.0.0.1/22' 2>/dev/null || exit 1; \
      else \
        tailscale status --peers=false >/dev/null || exit 1; \
      fi

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
