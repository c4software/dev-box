# The terminal: clipboard, opening files, file manager, notifications

There is no display, no Wayland and no D-Bus in the box. A few shims in
`/usr/local/bin` make the usual desktop commands work through the terminal you
are connected from.

## Copying to the clipboard

The image ships `/usr/local/bin/wl-copy` and `wl-paste`. The `copy` function of
the dotarchy config calls `wl-copy`, and there is no Wayland in the box, so the
shim does two things instead. It puts the text in the tmux buffer, which you
paste with prefix + `]`, and it relays it to the terminal with OSC 52. That
also fills the clipboard of the machine you are connected from over SSH, as
long as its terminal supports OSC 52. Alacritty, Ghostty, Kitty and foot do.
Outside tmux the shim sends OSC 52 directly. `wl-paste` prints the tmux buffer
back.

## Opening a URL, a file or a directory

There is no browser either. `/usr/local/bin/xdg-open` is a shim, and `BROWSER`
points to it system-wide, ahead of the dotarchy default. What it does depends
on the argument:

- a URL is copied into your clipboard through `wl-copy`, and one line says so.
  This is what `gh auth login`, the OAuth flows of the agents and the `repo`
  alias of the dotarchy config go through;
- a directory opens in `yazi`, a file in `$EDITOR` (nvim), in a new tmux pane
  next to the current one: below it, or to its right when the pane is wide
  enough (more than three times wider than tall) to be split in two. Outside
  tmux it runs in the foreground. `open .` from the dotarchy aliases therefore
  gives you a file manager next to your shell;
- an image (SVG aside, which is text and goes to the editor) is drawn by
  `chafa` in a floating tmux pane centered over the window, 90% of its size;
  any key closes it. Enter on a picture in yazi comes here too. A floating pane
  (tmux 3.7) rather than `display-popup`, which draws no image.

The `open` function discards the output of `xdg-open`, so its messages arrive
as a terminal notification through `notify-send` instead (see below). `EDITOR`
and `VISUAL` are set to `nvim` system-wide for the same reason: a pane opened
by a command only carries the environment of the login shell, not the exports
of the dotarchy config, and yazi would otherwise fall back on `vi`, which the
image does not ship.

## The file manager

yazi is the file manager, and the box gives it what it needs to be more than a
directory listing:

- **images are drawn by your terminal.** yazi asks the terminal what it can do
  (Kitty graphics, Sixel, iTerm2 inline images) and the answer travels through
  tmux and SSH, so a picture, a PDF page or an SVG shows up in the preview pane
  in Ghostty, Kitty, WezTerm or foot. It also sets `allow-passthrough all` on
  its own pane. For a terminal that draws nothing (Alacritty, a plain xterm),
  the image is rendered as text by `chafa`. The image ships `chafa`, `7zip`
  (archives), `resvg` (SVG), `imagemagick` (HEIC, AVIF, fonts) and `poppler`
  (PDF). Video thumbnails need `ffmpeg`, left out of the image for its size:
  `devbox dev-env media` installs it and brings it back after every rebuild.
  `yazi --debug` lists what yazi found, and which protocol it settled on;
- **`c c` copies the path into your clipboard**, `c f` the file name, `c d` the
  directory, as yazi does everywhere: it sends OSC 52 straight to the terminal,
  and calls `wl-copy`, which is the shim described above. Both roads end in the
  clipboard of the machine you are connected from, and in the tmux buffer;
- **`c t` sends the selected files to another machine**, over Taildrop. The
  chord runs `devbox tailscale send` on the selection (or the hovered file), a
  menu asks which machine among the ones online, and the screen waits for
  enter before going back to yazi. It comes from `~/.config/yazi/keymap.toml`,
  a file the image seeds and never overwrites once you changed it (see
  [customization.md](customization.md#seeded-files-and-devbox-seed) for how
  the seed works), so it is the place for your own bindings too. `~` in yazi
  lists them all.

## Desktop notifications

The image also ships `/usr/local/bin/notify-send`. There is no D-Bus in the
box, so the shim writes the notification to the terminal as OSC 777 instead,
wrapped in a tmux passthrough sequence when it runs inside tmux. SSH carries it
like any other output and the terminal you are connected from shows it as a
desktop notification. foot, Kitty, Ghostty and WezTerm support OSC 777;
Alacritty does not. The usual `notify-send` options are accepted and ignored,
only the summary and the body are sent. Only the terminal attached to the tmux
session receives it, a detached session notifies nobody, and a pane that is
not visible needs `allow-passthrough all` in the tmux config rather than `on`.

```bash
notify-send "Build finished" "42 tests passed"
```
