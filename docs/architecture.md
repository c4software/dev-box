# Architecture, design choices and contributing

## Two layers

The image is disposable, the home is not.

- **The image** comes from the repository: `rootfs/` mirrors it, so
  `rootfs/usr/local/bin/devbox` in the repo becomes `/usr/local/bin/devbox` in
  the container. The `Dockerfile` builds it, `compose.yaml` runs it,
  `setup.sh` installs a box without a clone and `scripts/` holds the backup and
  restore. System packages come from pacman, in the image. Anything changed in `/usr/local/bin`, `/etc/devbox` or
  `/usr/share/devbox` inside the box is lost on the next rebuild.
- **The home** lives in `./data/home` on the host and survives every rebuild
  (see [backup.md](backup.md#what-persists)). Dev tools come from mise, in the
  home.

At every start, the entrypoint creates the user if missing, lays down the
shipped config (the seed), links the agent skill, runs the pending migrations,
reinstalls the persistent packages, starts Tailscale or sshd and, when enabled,
podman. On the very first start it also syncs the dotfiles and installs the
mise tools, in the background. The detailed walk through, with every path of
the image and of the home, is
[`architecture.md`](../rootfs/usr/share/devbox/skills/devbox/architecture.md)
in the agent skill.

## Design choices

- **No host Docker socket.** Mounting it would amount to root on the host. When
  containers are needed inside the box, rootless podman with the `docker` shim
  answers instead, as an opt-in. It costs part of the box's own isolation, so
  the default keeps the container as tight as Docker makes it.
- **Tailscale inside the container.** The box is only reachable from the
  tailnet, nothing is published on the host, and Tailscale SSH handles
  authentication.
- **amd64 and arm64.** The official `archlinux` image exists only for x86_64,
  so arm64 builds (Raspberry Pi 5) use Arch Linux ARM through the community
  image `menci/archlinuxarm:base`, rebuilt daily. BuildKit picks the base from
  `TARGETARCH`, and the rest of the image assumes nothing about the
  architecture.
- **Fixed UID/GID 1000:1000.** Same owner as on the host for the bind-mounted
  volumes.
- **One image for everyone, customised at run time.** The published image
  bakes in nothing from `.env`: user, volumes, Tailscale, dotfiles and dev
  environments are read by Compose when the container starts, so the same
  image serves every box.
- **Nothing updates behind your back.** A background check, a line at login,
  and `devbox update` when you decide. Migrations are the only thing that runs
  on its own, because they arrive with the image that needs them.

## Contributing

Read [`AGENTS.md`](../AGENTS.md) first: how the repository maps to the box, the
rule that a structural change ships with a migration, where each kind of
change goes, and the conventions (bash, shellcheck, English, plain prose). The
recipe for each kind of change, and how to test in a throwaway container
without touching your own box, is
[`extending.md`](../rootfs/usr/share/devbox/skills/devbox/extending.md).

Adding a `devbox` command is dropping a `dev-box-<name>` script with its
`# devbox:` headers (see [commands.md](commands.md#how-it-finds-its-commands)).
Adding a dev environment is one script in
`rootfs/usr/share/devbox/dev-envs/` (see
[dev-envs.md](dev-envs.md#how-an-environment-is-written)). Adding a seeded
file is a file in `rootfs/etc/devbox/`, a line in the `SEEDS` array of
`dev-box-seed`, and a row in the seed table of
[customization.md](customization.md#seeded-files-and-devbox-seed).

When a command, a variable or a seeded file changes, update the page of
`docs/` that describes it, and the [README](../README.md) when it is one of the
essentials listed there.

### Publishing a release

A change a user of the box notices goes in the annotation of the next release
tag. `git tag -a v1.7` opens the editor for the notes, `git push origin v1.7`
starts the workflow, which builds the image, publishes it on
`ghcr.io/c4software/dev-box` (see
[manual-install.md](manual-install.md#prebuilt-image)) and then creates the
GitHub release from that text. That release is what `devbox changelog` and the
next login show (see [updates.md](updates.md#the-changelog-at-login)).
