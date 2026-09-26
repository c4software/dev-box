# Databases

`devbox dbs` starts a development database in a podman container inside the
box. Same images and same development options as `omarchy-install-docker-dbs`
on the host: no password, or a password you already know. It needs rootless
podman enabled (see [containers.md](containers.md)). Without it, it prints the
three steps and stops instead of starting half of the containers.

```bash
devbox dbs                          # menu: start, stop, start again, remove or purge, then several at a time
devbox dbs postgres redis           # start these two
devbox dbs --list                   # image, port and current state of each
devbox dbs --stop redis             # stop it, keep everything
devbox dbs --start redis            # start it again
devbox dbs --remove redis           # drop the container, keep the data
devbox dbs --remove --purge redis   # drop the data too, asks for confirmation
```

![dev-box-dbs --list in the box: the six databases with their image, their port and their state, postgres and redis up](screenshots/dev-box-dbs-list.png)

| Name | Image | Port | Credentials |
| --- | --- | --- | --- |
| `mysql` | `mysql:8.4` | 3306 | user `root`, empty password |
| `postgres` | `postgres:18` | 5432 | user `postgres`, `trust`, no password |
| `mariadb` | `mariadb:11.8` | 3306 | user `root`, empty password |
| `redis` | `redis:7` | 6379 | none |
| `mongodb` | `mongo:noble` | 27017 | `admin` / `admin123` |
| `mssql` | `mcr.microsoft.com/mssql/server:2022-CU12-ubuntu-22.04` | 1433 | `sa` / `@dmin123`, amd64 only |

Each container is named `devbox-<name>` and keeps its data in a podman volume
called `devbox-<name>`. `--remove` drops the container and leaves the volume,
so `devbox dbs <name>` right after comes back on the same data. `--purge` is
the only thing that deletes it, and it asks first.

`mysql` and `mariadb` both want port 3306: starting the second one is refused,
with the name of the one already running. `mssql` has no arm64 image, so it is
refused on a Raspberry Pi 5 rather than failing on a pull.

Ports are published on `127.0.0.1`, as they are on the host, so a database is
reachable from inside the box only: `psql -h 127.0.0.1 -U postgres`. From your
laptop, go through an SSH tunnel to the box:

```bash
ssh -L 5432:127.0.0.1:5432 dev@dev-box
```

`devbox serve --tcp 5433:5432` is the other way, on the tailnet (see
[access.md](access.md#reaching-a-dev-server)).

Nothing restarts on its own, here as everywhere else in the box. After a
restart of the container, bring a database back with `devbox dbs postgres`,
which starts the existing container instead of creating a new one, or with
`devbox dbs --start postgres`.
