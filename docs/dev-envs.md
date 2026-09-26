# Dev environments

`devbox dev-env` installs or removes a whole language environment in one call,
through mise. No `curl | sh`, and no pacman except for PHP, the browser and
media (see below). Whatever mise installs is declared in
`~/.config/mise/config.toml`, survives a rebuild, and is upgraded by
`devbox update tools` like the rest.

```bash
devbox dev-env --list             # what is on offer, and what is installed
devbox dev-env --info ruby        # what one installs, and what a removal leaves
devbox dev-env node go            # install these two
devbox dev-env --remove node go   # remove them
devbox dev-env                    # menu: install or remove, then several at a time
```

![dev-box-dev-env --list in the box: the environments with a one line description each](screenshots/dev-env-list.png)

Without arguments it first asks whether to install or remove, then opens a gum
menu with multiple selection, the environments on the left and their
description on the right. The remove menu only offers what is installed.
Running it again on an environment already installed, or already removed,
changes nothing.

## `DEV_ENVS`: environments installed at start

The same environments can be asked for from `.env`: `DEV_ENVS="node go python"`
and every start makes sure they are there, through
`devbox dev-env --if-missing`, in the background after the mise tools. The
setup script asks for this list. What is installed already is
skipped, so a start only spends time on a fresh home or a name added since. An
unknown name refuses the whole list, nothing is installed. The output goes to
`~/.cache/dev-box/dev-envs.log`; while it runs, and when it failed, the login
message and `devbox status` say so on one line, and the line disappears once
everything is there.

`DEV_ENVS` never removes anything: take a name out of the list and the
environment stays until `devbox dev-env --remove`. The other way round, an
environment listed in `DEV_ENVS` cannot be removed, since the next start would
install it again: `devbox dev-env --remove` refuses it and the remove menu
leaves it out. Take it out of `.env` first, restart the container, then remove it.

## What a removal leaves

A removal takes the tools out of `~/.config/mise/config.toml` with
`mise unuse -g`, which also prunes the versions no other config needs. It only
removes what the environment itself brought: `laravel` drops the installer but
keeps PHP and Node, `phoenix` drops the `phx_new` archive but keeps Elixir,
`scala` keeps Java, and the message says how to remove the base. Project data
is never touched: `~/go`, `~/.cargo`, `~/.mix`, `~/.m2`, `~/.config/composer`
and the like stay where they are, so a later `devbox dev-env <name>` finds
everything back.

## Environments that do more

A few of them do more than pull a runtime. `python` also installs `uv`. `ruby`
writes `~/.gemrc`, turns off `ruby.compile` so mise takes a precompiled build
instead of spending minutes on a compiler, and installs Rails. `elixir` runs
`mix local.hex`, and `phoenix` adds rebar and the `phx_new` generator. `rust`
is the mise toolchain, not rustup, so there is a single place where versions
are declared.

`android` is the platform-tools only, `adb` and `fastboot`, taken from the zip
Google publishes, through mise's http backend: no SDK manager, no platform, no
Java. That URL carries no version, so `devbox update tools` cannot refresh it;
run `devbox dev-env android` again to take the latest build. The zip also
carries an old `sqlite3`, which the command removes so that the one of the
image stays first on the PATH. Google publishes no arm64 build, so on an arm64
box the command points to `devbox pkg add android-tools` instead.

`android-sdk` is the full SDK, to build apps: the cmdline-tools from the mise
registry, pinned to the version of the day so that `devbox update tools` never
moves `ANDROID_HOME`, then `sdkmanager` lays the platform-tools, the newest
stable platform and build-tools inside it, the licenses accepted on your
behalf. It needs a JDK 17 or 21: `java@temurin-21` when no java is declared,
the declared one otherwise. There is no emulator (no KVM, no display): deploy
to a phone over USB or `adb connect`. `flutter` sits on it, from the official
stable archive through mise, with the Android and web engine artifacts fetched
at install and Linux desktop turned off; the web target runs with
`flutter run -d web-server --web-hostname 0.0.0.0`. Both are x86_64 only,
Google publishes no arm64 build-tools. Swift is not offered: swift.org
publishes no build for Arch, and the Ubuntu one needs library aliases to start.

## The exceptions: PHP, browser, media

PHP is the one exception. mise can only build PHP from source, which takes
minutes and needs a pile of development headers, so `php`, `composer`,
`php-sqlite`, `php-gd`, `php-sodium` and `xdebug` are pacman packages baked
into the image, with the usual extensions and xdebug already enabled at build
time. `devbox dev-env php` only checks and shows what is there. `laravel` adds
Node and the Laravel installer through `composer global`, kept in
`~/.config/composer`, which is in the PATH and in the persistent home.
`symfony` adds `symfony-cli` through mise's github backend.

`browser` is the other exception: a headless Chromium, with `noto-fonts` so
that emojis and non Latin scripts do not render as squares, so that a coding
agent can screenshot a dev server and look at the result. The mise registry
only offers `playwright` and `agent-browser`, which download a Chromium built
for Debian and Ubuntu and still need a pile of pacman libraries, so the
environment installs the distribution package through
`devbox pkg add chromium noto-fonts` instead: it works as it is on amd64 and on
Arch Linux ARM, and `devbox pkg` reinstalls it after a rebuild. Chromium is not
baked into the image because it weighs about half a gigabyte and most boxes
never need it. How to use it, screenshots, DOM dumps and Playwright on the
system Chromium, is in the
[`browser.md`](../rootfs/usr/share/devbox/skills/devbox/browser.md) guide of
the agent skill.

`media` gathers the tools to fetch, convert and inspect audio, video and
pictures. `yt-dlp` and `oxipng` come through mise, so `devbox update tools`
keeps `yt-dlp` current: it breaks whenever a site changes. The rest goes
through `devbox pkg`, like the browser: `ffmpeg` (the mise registry only builds
it from source), `pngquant`, `jpegoptim`, `cwebp` (`libwebp-utils`),
`exiftool`, `mediainfo` and `aria2`. `ffmpeg` stays out of the image for its
size; once there, yazi shows video thumbnails. YouTube wants a JavaScript
runtime for `yt-dlp`: `devbox dev-env deno`. A removal takes everything out,
`ffmpeg` included.

OCaml is not offered: upstream it goes through the opam installer, which would
be wiped by the next image rebuild.

## How an environment is written

Each environment is a short script with three functions, `details`, `install`
and `uninstall`, plus `is_installed` when the mise config cannot tell and
`is_supported` when it does not run everywhere. What this machine cannot take
(`android`, `android-sdk` and `flutter` on arm64) is left out of the menu and
the list, and skipped by `DEV_ENVS`, so one `.env` serves both architectures.
The image ships them in `/usr/share/devbox/dev-envs/`, and `devbox dev-env`
finds every file there on its own.

A script of the same shape in `~/.config/dev-box/dev-envs/<name>.sh` adds an
environment to your box, or replaces the image's one of the same name, and
survives rebuilds since it lives in the home; `--list` marks it. The format is
described at the top of `/usr/share/devbox/lib/dev-env.sh`, and copying one of
the image's scripts is the quickest start. To ship one in the image for every
box, see
[`extending.md`](../rootfs/usr/share/devbox/skills/devbox/extending.md).
