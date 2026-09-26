# Persistence, backup and restore

## What persists

Three bind mounts under `./data/` (git-ignored). A rebuild of the image, or a
new image, loses nothing:

| Host | Container | Contents |
| --- | --- | --- |
| `./data/home` | `~` | config, mise toolchains, nvim plugins, pi/omp sessions, zsh history, SSH host keys, podman images |
| `${PROJECTS_DIR:-./data/projets}` | `~/projets` | your repositories |
| `./data/tailscale` | `/var/lib/tailscale` | tailscaled state (node identity) |

`~/projets` is a separate volume so it can be backed up, shared or pointed at
another disk independently. Only its top-level directory is ever chowned, when
Docker created it as root. Its contents are never touched. You can start from a
fresh home (`rm -rf data/home`) without affecting your projects.

## Backup

`scripts/backup.sh [--with-tailscale] [dest_dir]` writes
`dev-box-<TS_HOSTNAME>-<YYYYmmdd-HHMMSS>.tar.zst` into `dest_dir`, `./backups`
by default (git-ignored). It needs `zstd` on the host. The setup script
installs both scripts in the install directory too.

What goes in:

- `data/home`, minus the caches that rebuild themselves: `.cache`,
  `.local/share/{mise,nvim,dotarchy,lazyvim-starter}`, `.local/state/nvim`,
  `.npm`, `.bun`, and `.local/share/containers`, the podman image store, which
  is bulky, re-pullable, and full of files owned by mapped UIDs.
- The projects directory (`PROJECTS_DIR`), minus every `node_modules`.
  `.git/objects` is kept, so your repositories come back whole, with their
  history.
- A copy of `.env` and `compose.override.yaml` when they exist. `.env` holds
  `TS_AUTHKEY` and `GITHUB_TOKEN`, so treat the archive as a secret.

What stays out: `data/tailscale`. It holds the node identity, and restoring it
elsewhere would give you two machines claiming the same one. Pass
`--with-tailscale` if you really want it in the archive.

Ownership is preserved (`--numeric-owner`), and `sudo` is used only when
something that goes into the archive is not readable as you. The archive is
read back end to end after being written, and its entry count and size are
printed.

## Restore

```bash
./scripts/restore.sh backups/dev-box-dev-box-20260920-101500.tar.zst
```

It stops the container, lists what already exists and would be overwritten,
asks for confirmation, then unpacks at the root of the repo. Files are
overwritten one by one. Nothing outside the archive is ever deleted, so a home
restored over a newer one keeps whatever the archive does not mention. Add
`--yes` to skip the prompt. Outside a terminal the script refuses to run
without it. Then bring the box back with `docker compose up -d`. The mise toolchains were
not in the archive, so the start reinstalls them, or you run
`devbox update tools` from inside.

If `PROJECTS_DIR` points outside the repo, on another disk, the projects are
stored under `projets-external/` in the archive and restored there. Move them
back yourself, the script will not write outside the repo.
