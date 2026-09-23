# dev-box changelog

What changed in the box, newest first. `devbox changelog` prints it, and the
first login after an update shows the entries that are new, three at most.

One entry per change a user of the box notices: a `## YYYY-MM-DD Title` line,
then one or two lines saying what it does and what to run. The heading is what
the box remembers as seen, so never edit the heading of a published entry.

## 2026-09-23 Is this image the latest?
`devbox check --image` compares the box with the newest release of the repo,
and `devbox changelog --upcoming` shows what the next image brings.

## 2026-09-23 A changelog in the box
`devbox changelog` lists what changed in the box. The first login after an
update shows the new entries, three at most.

## 2026-09-23 yazi previews images, c t sends a file over Taildrop
Images, PDF, SVG and archives are previewed in yazi, and the seeded keymap
sends the hovered file to another machine with `c t`.

## 2026-09-23 shellcheck in every box
shellcheck ships through the seeded mise config: `devbox seed` picks it up on
a box that never edited its config.

## 2026-09-23 devbox tui, a catalogue of terminal apps
btop, lazydocker, atac, rainfrog and a dozen others, installed on demand and
kept across rebuilds: `devbox tui`.

## 2026-09-23 open a directory in yazi, a file in nvim
`open <dir>` and `open <file>` open a tmux pane with yazi or nvim; a URL goes
to the clipboard.

## 2026-09-23 A guided tour of the box
`devbox tour` walks through the box in a dozen steps, and the first login of a
new home proposes it.

## 2026-09-22 DEV_ENVS installed at start
`DEV_ENVS="node go"` in `.env` on the host installs those environments at
start when they are missing. `devbox status` shows where it stands.
