# shellcheck shell=bash
# dev-box: the topics of `devbox help`, found on disk. Sourced by dev-box-help,
# not run.
#
# A topic holds the steps a command cannot do on its own: an account to sign
# in to, a download behind a login, a cable to plug, a file to edit on the
# host. One topic is one text file, <name>.txt, in one of two directories:
#   /usr/share/devbox/help      shipped with the image
#   ~/.config/dev-box/help      the user's own, kept across rebuilds; a file
#                               here wins over the image's of the same name
# The name is the file name without .txt: lowercase letters, digits, - and _.
#
# The file is printed as it is, so its layout is the contract:
#   line 1     the title, 64 characters at most, not indented: the menu and
#              --list show it next to the name
#   line 2     empty
#   then       an optional introduction, indented by 2
#   steps      "  1. Title", numbered from 1 without a gap, at least one. A
#              step done outside the box says where in its title ("On the
#              host", "On your machine")
#   sections   optional, after the steps: "  Title", indented by 2 like a
#              step, without a number. "  Sources" comes last, when the steps
#              were taken from somewhere
#   text       of a step or a section: indented by 5
#   commands   one per line, indented by 7, what it does after it on the
#              same line when that helps
# Nothing is indented by 1, 3 or 4. 78 columns at most, a line made of one
# URL aside. ASCII only, no tab, no space at the end of a line, one empty
# line at most in a row, none at the end.
#
# `devbox help --check` holds every topic to it.

HELP_SYSTEM_DIR="${HELP_SYSTEM_DIR:-/usr/share/devbox/help}"
HELP_USER_DIR="${HELP_USER_DIR:-$HOME/.config/dev-box/help}"
HELP_TITLE_MAX=64
HELP_WIDTH=78

# HELP_NAMES: every name, sorted. HELP_FILES[name]: the file that wins.
# shellcheck disable=SC2034 # read by dev-box-help
declare -a HELP_NAMES=()
declare -A HELP_FILES=()

help_load() {
  local f name
  HELP_NAMES=()
  HELP_FILES=()
  # The user's directory first: the first file seen for a name is the one kept.
  for f in "$HELP_USER_DIR"/*.txt "$HELP_SYSTEM_DIR"/*.txt; do
    [ -f "$f" ] || continue
    name="${f##*/}"
    name="${name%.txt}"
    [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || continue
    [ -n "${HELP_FILES[$name]:-}" ] && continue
    HELP_FILES[$name]="$f"
  done
  [ "${#HELP_FILES[@]}" -gt 0 ] || return 0
  # shellcheck disable=SC2034 # read by dev-box-help
  mapfile -t HELP_NAMES < <(printf '%s\n' "${!HELP_FILES[@]}" | LC_ALL=C sort)
}

help_exists() { [ -n "${HELP_FILES[$1]:-}" ]; }

# help_title <name>: the first line of the topic.
help_title() {
  local line=""
  IFS= read -r line < "${HELP_FILES[$1]}" || true
  printf '%s\n' "$line"
}

# help_body <name>: the topic without its title and the empty line under it.
help_body() { tail -n +3 "${HELP_FILES[$1]}"; }

# help_check <file>: prints what breaks the contract, one "file:line: reason"
# per line, and exits 1 when there is any.
help_check() {
  LC_ALL=C awk -v file="$1" -v tmax="$HELP_TITLE_MAX" -v width="$HELP_WIDTH" '
    function bad(msg) { printf "%s:%d: %s\n", file, NR, msg; failed = 1 }
    {
      if ($0 ~ /\t/) bad("a tab")
      if ($0 ~ /[ ]$/) bad("a space at the end of the line")
      if ($0 ~ /[^\t -~]/) bad("a character that is not ASCII")
    }
    NR == 1 {
      if ($0 == "" || $0 ~ /^ /) bad("line 1 is the title, not indented")
      if (length($0) > tmax) bad("the title is over " tmax " characters")
      next
    }
    NR == 2 {
      if ($0 != "") bad("line 2 is empty")
      next
    }
    $0 == "" {
      if (blank) bad("two empty lines in a row")
      blank = 1
      next
    }
    {
      blank = 0
      if (length($0) > width && $0 !~ /^ +[a-z]+:\/\/[^ ]+$/)
        bad("over " width " columns")
      match($0, /^ */)
      indent = RLENGTH
      if (indent != 2 && indent < 5) {
        bad("indented by " indent ": 2 for a step, a section or the introduction, 5 for their text, 7 for a command")
        next
      }
      if (indent == 2 && $0 ~ /^  [0-9]+\. /) {
        n = $1 + 0
        if (sections) bad("step " n " comes after a section")
        if (n != steps + 1) bad("step " n " where step " steps + 1 " is expected")
        steps = n
      } else if (indent == 2 && steps > 0) {
        sections = 1
      }
    }
    END {
      if (NR < 3) { printf "%s: no steps\n", file; failed = 1 }
      else if (steps == 0) { printf "%s: no numbered step\n", file; failed = 1 }
      if (blank) { printf "%s: an empty line at the end\n", file; failed = 1 }
      exit failed
    }' "$1"
}
