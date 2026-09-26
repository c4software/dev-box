# Access: Tailscale, Headscale, SSH and Taildrop

The box is reached in one of two ways, never both:

- **Tailscale** (the default): `tailscaled` runs inside the container and
  Tailscale SSH opens the shell. Nothing is published on the host. Headscale
  works too.
- **Plain SSH** (`TS_DISABLE=true`): the box runs its own OpenSSH server on a
  published port, public key only.

## Connecting

```bash
ssh dev@dev-box                # Tailscale, from any machine of the tailnet
ssh -p 2222 dev@127.0.0.1      # TS_DISABLE=true, from the host
docker exec -it -u dev dev-box zsh -l   # always works, on the host
```

The login shell runs `exec tmux new-session -A -s "$(hostname)" -c ~`. You
always land in zsh in the same tmux session, named after the box
(`TS_HOSTNAME`, `dev-box` by default), starting in your home directory.
Running several boxes side by side therefore gives each one a session of its
own. To get a plain shell instead:

```bash
ssh -t dev@dev-box env NO_TMUX=1 zsh
```

The user is created at container start, if missing, with UID/GID 1000:1000,
zsh as shell and passwordless sudo. The home itself is persistent.

## Tailscale and Headscale setup

On first start the box prints a login URL in `docker compose logs -f` (the
setup script prints it for you). Open it, or feed it to
`headscale nodes register`, to attach the machine. With `TS_AUTHKEY` set in
`.env`, it attaches on its own. The node identity is then kept in
`./data/tailscale`, so this happens only once. `TS_LOGIN_SERVER` selects
Tailscale (the default) or your Headscale URL, `TS_EXTRA_ARGS` is appended to
`tailscale up`.

Tailscale SSH is refused without an `ssh` rule in the policy, and the `ssh`
rule alone does not open the network. As soon as the policy contains `grants`
or `acls`, traffic to the box must be allowed too, otherwise port 22 is
filtered. This policy was validated with Headscale v0.29.3
(`headscale policy check`):

```json
{
  "grants": [
    { "src": ["alice@"], "dst": ["alice@"], "ip": ["*"] }
  ],
  "ssh": [
    { "action": "accept", "src": ["alice@"], "dst": ["alice@"], "users": ["dev"] }
  ]
}
```

- `src` and `dst`: the Headscale user owning the machines, the one the box was
  registered to.
- `users`: the Unix account inside the box (`USER_NAME`).
- A `user@` SSH destination requires `src` to contain only that same user.

## Reaching a dev server

A server listening on `0.0.0.0` inside the box is already reachable from the
tailnet at `http://<TS_HOSTNAME>:<port>`, as long as the Headscale policy
allows the port. The example grant above does, with its `"ip": ["*"]`. Nothing
else to set up, and a server bound to `127.0.0.1` is not reachable that way.

`devbox serve` is the other form: `tailscale serve` proxies the port for you,
which also works for a server bound to `127.0.0.1` only.

```bash
devbox serve               # menu: publish, tcp, status or off, gum asks the port
devbox serve 3000          # tailscale serve --bg --http=3000 3000
devbox serve 8080:3000     # listen on 8080, proxy to 127.0.0.1:3000
devbox serve --on 8080 3000   # the same thing, written out
devbox serve --tcp 5433:5432  # raw TCP passthrough
devbox serve status        # what is served right now
devbox serve off 3000      # stop that one, or "off all" for every mapping
```

It prints the URL it published, `http://dev-box.home.arpa:3000/`. A single
port means the same port on both sides; the first port of a pair is the one
the tailnet sees, the second is the port the app listens on in the box.

HTTPS and Funnel are not available with Headscale: the https mode answers
`error 501 Not Implemented`, so this is plain http, inside the tailnet, and
never on the Internet. To reach the port from outside the tailnet, map it in
`compose.override.yaml` or tunnel it with
`ssh -L 3000:127.0.0.1:3000 dev@dev-box`.

## SSH without Tailscale

Set `TS_DISABLE=true` in `.env` and the box starts its own OpenSSH server
instead of `tailscaled` (the setup script does this with `--access ssh`).
Public key only. Password and root login are refused:

```bash
TS_DISABLE=true
SSH_AUTHORIZED_KEYS="ssh-ed25519 AAAA... you@laptop"
SSH_BIND=127.0.0.1   # 0.0.0.0 to expose it on the LAN
SSH_PORT=2222
```

```bash
ssh -p 2222 dev@127.0.0.1
```

The keys are rewritten into `~/.ssh/authorized_keys` at every start, so `.env`
is the source of truth. Host keys are generated once into
`~/.config/dev-box/ssh` and live in the persistent home, so you never get a
"host key changed" warning after a rebuild.

With `SSH_AUTHORIZED_KEYS` empty, sshd is not started at all. The container
stays up and reports unhealthy, and you get in with
`docker exec -it -u dev dev-box zsh -l`.

With `TS_DISABLE=true`, the commands that need a tailnet (`devbox serve`,
`devbox tailscale`) leave the menu, and say why when called.

## Taildrop

`devbox tailscale` moves files between the box and the other machines of your
tailnet, without going through a shell on the host.

```bash
devbox tailscale                      # menu: send (machine, then file), receive, status
devbox tailscale send laptop notes.md build.log
devbox tailscale send build.log       # no machine given: a menu picks one online
devbox tailscale receive              # waits, saves into ~/inbox
devbox tailscale receive --once ~/tmp # one delivery, then stop
devbox tailscale status               # the link and its peers
```

When `send` gets files and no machine, it asks which one with a menu of the
peers online right now, which is what the `c t` chord of yazi relies on (see
[terminal.md](terminal.md#the-file-manager)). `receive` loops on
`tailscale file get --wait`, so it can sit there for hours; `--once` returns
after the first delivery. The default directory is `~/inbox`, created if
missing. With `TS_DISABLE=true` there is no tailnet at all, and the command
says so and exits 1 rather than failing obscurely.

Taildrop also works with Headscale, version 0.23 and later, between machines
that belong to the same user.
