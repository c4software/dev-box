# Troubleshooting

## Let the agent look: `devbox diagnostic`

```bash
devbox diagnostic "postgres does not start"   # the agent, on that problem
devbox diagnostic                             # the agent, looking for anything wrong
devbox diagnostic --report > ~/diagnostic.txt # the facts, no agent, to share
```

`devbox diagnostic` starts your default coding agent (see
[agents.md](agents.md)) on the box's diagnostic guide: it gathers facts with
read-only commands, says what is wrong, and asks before changing anything.
When the fix is on the host (`.env`, `compose.override.yaml`, `just up`), it
prints the commands for you to run there.

`--report` prints the same facts without an agent, to paste to someone (a
teacher, a colleague, an issue): the image and access, the default agent,
disk and memory, ownership of the home, the shipped config, pending
migrations, mise, the `DEV_ENVS` state, the persistent packages, podman and the
databases, DNS and HTTPS reachability, and the tails of the start logs. Every
command in it is read only and bounded by a timeout, and it prints no secret,
but read it before sending it. `--prompt` prints the instruction given to the
agent, to paste elsewhere, and `--dry-run` shows which agent would run.

The procedure the agent follows, with the known causes by symptom, is
[`diagnostic.md`](../rootfs/usr/share/devbox/skills/devbox/diagnostic.md) in
the agent skill.

## By hand

- **What is the box doing?** `devbox status` in one call: the commit the image
  was built from, Tailscale or sshd, podman, the active mise tools, and
  anything pending.
- **What differs from a stock box?** `devbox override` lists every change made
  to this box, with how to undo each (see
  [customization.md](customization.md#reviewing-it-all-devbox-override)).
- **Logs.** `docker compose logs -f` (or `just logs`) on the host shows the
  entrypoint, `dotarchy-sync`, `dev-box-seed` and `tailscale up` output,
  including the login URL when `TS_AUTHKEY` is empty.
- **Run without Tailscale.** See
  [SSH without Tailscale](access.md#ssh-without-tailscale). With no
  `SSH_AUTHORIZED_KEYS` set, sshd does not start, the container stays up and
  reports unhealthy. Get in with `docker exec -it -u dev dev-box zsh -l`.
- **mise install failed.** See `~/.cache/dev-box-install.log`. Rate-limit
  errors usually mean `GITHUB_TOKEN` is missing.
- **A dev environment of `DEV_ENVS` failed.** See
  `~/.cache/dev-box/dev-envs.log`; `devbox status` and the login line say so.
- **SSH refused, or port 22 filtered.** Check the Headscale policy: both the
  `ssh` rule and a `grants`/`acls` rule allowing traffic to the box are
  required (see [access.md](access.md#tailscale-and-headscale-setup)).
- **Healthcheck.** Every 60 s: `tailscale status --peers=false`, or a
  connection to port 22 when `TS_DISABLE=true`.
- **`docker` says it cannot reach the API.** The podman socket did not start,
  or podman is off. See `~/.cache/dev-box-podman.log`, and check
  `PODMAN_ENABLE` and the podman block of `compose.override.yaml` (see
  [containers.md](containers.md)).
- **A change in `/usr/local/bin`, `/etc/devbox` or `/usr/share/devbox` is
  gone.** Those come from the image and are replaced by every rebuild. See
  [customization.md](customization.md) for the places that last.
- **A dotfiles tweak keeps coming back to the old value.** `devbox sync`
  overwrote it: put it in `~/.config/dev-box/overrides/` (see
  [customization.md](customization.md#dotfiles-sync-and-overrides)).
- **The setup script refuses to run.** It says why and what to do: Docker
  missing or not answering, permission denied on the Docker socket (join the
  `docker` group, do not use `sudo`), a directory that is not empty, or a
  container named `dev-box` started from another directory (see
  [manual-install.md](manual-install.md#the-setup-script)).
