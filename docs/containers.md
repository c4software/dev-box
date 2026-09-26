# Containers inside the box (podman and docker)

`docker run`, `docker build` and `docker compose` can work inside the box,
without the host's Docker socket and without a privileged container. What
answers is [podman](https://podman.io/) running rootless as your user. It is
off by default, because nesting it forces the box's own isolation open: the
seccomp profile, the read-only `/proc/sys` and AppArmor all have to be lifted
for the container, which makes a container-to-host escape easier than it is
otherwise.

## Turning it on

On the host:

1. uncomment the podman block (`/dev/fuse` and the three `security_opt`) in
   `compose.override.example.yaml`, copied to `compose.override.yaml`;
2. set `PODMAN_ENABLE=true` in `.env`;
3. restart the container: `docker compose up -d`.

The setup script does steps 1 and 2 for you when you answer yes to its
podman question, unless a `compose.override.yaml` already exists (then add
the block by hand). Why each line of the block is needed is
written in `compose.override.example.yaml`: `/dev/fuse` for fuse-overlayfs,
`seccomp` because the default profile refuses `clone(CLONE_NEWUSER)`,
`systempaths` because a read-only `/proc/sys` stops crun and netavark, and
`apparmor` where AppArmor is active (Debian, Raspberry Pi OS). No
`--privileged` and no `CAP_SYS_ADMIN`.

Then:

- `podman-docker` provides `/usr/bin/docker` as a shim over the `podman` CLI;
- the entrypoint starts `podman system service` as your user on
  `/run/user/1000/podman/podman.sock`, and login shells export
  `DOCKER_HOST=unix:///run/user/1000/podman/podman.sock`, so Compose v2 (the
  `docker-compose` package, a real Docker plugin) and anything else that talks
  to the socket finds it;
- images live in `~/.local/share/containers`, in the persistent home. They are
  outside the backup, so they re-pull.

```bash
docker run --rm alpine echo ok
docker build -t mine .
docker compose up -d && docker compose ps
```

## When it is off

With `PODMAN_ENABLE=false` no socket is started and `DOCKER_HOST` is not set.
`docker` and `podman` then go through a wrapper that stops with the three steps
above instead of an obscure error:

![A docker ps call inside the box with podman disabled: the wrapper answers that podman is not active and lists the three steps to enable it](screenshots/podman-wrapper.png)

The same wrapper points to `~/.cache/dev-box-podman.log` when podman is enabled
but the socket never came up. `PODMAN_FORCE=1 docker ...`, or
`/usr/bin/podman`, bypasses it.

## Known limits

- Containers started here are rootless. There is no `--privileged` inside the
  box, publishing a port below 1024 is refused, since it would need
  `net.ipv4.ip_unprivileged_port_start` lowered, and UIDs are mapped: a file
  written as root in a container belongs to `100000` on the host side of the
  bind mount.
- Networking goes through pasta/slirp4netns rather than a host bridge.
  Published ports are reachable from inside the box (`curl localhost:8080`).
  Reaching them from your laptop means going through the box's own address
  (Tailscale).
- Storage uses `fuse-overlayfs`, since overlayfs cannot always stack on the
  overlay the box itself runs on. It is correct everywhere, and slower than
  native overlay on heavy I/O.
- Docker on the host still owns the box itself. Restarting or rebuilding the
  container happens on the host, not in here.
- On a Raspberry Pi, rootless podman has not been confirmed on real hardware
  yet (see [manual-install.md](manual-install.md#raspberry-pi-5-arm64)).

With podman on, `devbox dbs` starts development databases in it, see
[databases.md](databases.md), and `devbox tui lazydocker` becomes useful.
