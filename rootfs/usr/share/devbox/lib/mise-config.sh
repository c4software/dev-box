# shellcheck shell=bash
# dev-box: the [tools] lines added to the global mise config, told apart from
# the rest of the file. Sourced by dev-box-seed and dev-box-override, not run.
#
# `mise use -g <tool>` (the agent wrappers, devbox dev-env, the wrappers of
# devbox mise-install, or a hand typed command) only ever inserts one line,
# `<tool> = "<version>"`, into [tools] of ~/.config/mise/config.toml, at the
# place mise picks. It never rewrites the lines already there, and
# `mise unuse -g` removes the line it added and nothing else. So a home copy
# that becomes the shipped reference again once its extra [tools] lines are
# taken out was never changed by hand: only tools were added to it. Those
# lines can be carried over, as they are, into a new shipped version.
#
# Anything else counts as a local change: another version for a tool the
# reference declares, a tool removed from it, a comment, a setting.
#
# Only one-line entries are recognised. A multi-line value added by hand
# leaves its other lines behind, so the file is a local change, as before.

# The awk helpers shared by every function below.
_MISE_CFG_AWK='
function is_header(l) { return l ~ /^[[:space:]]*\[/ }
function is_tools(l)  { return l ~ /^[[:space:]]*\[tools\][[:space:]]*(#.*)?$/ }
function is_entry(l)  { return l ~ /^[[:space:]]*[^#[:space:]=][^=]*=/ }
# The tool name of an entry, quotes taken off: "npm:x" = "latest" gives npm:x.
function tool(l,   k) {
  k = l
  sub(/^[[:space:]]+/, "", k)
  if (k ~ /^"/)      { sub(/^"/, "", k); sub(/".*$/, "", k) }
  else if (substr(k, 1, 1) == q) { k = substr(k, 2); k = substr(k, 1, index(k, q) - 1) }
  else               { sub(/[[:space:]]*=.*$/, "", k) }
  return k
}
'

# mise_cfg_tools <file>: the tools declared in [tools], one per line.
mise_cfg_tools() {
  [ -f "$1" ] || return 0
  awk -v q="'" "$_MISE_CFG_AWK"'
    is_header($0) { s = is_tools($0); next }
    s && is_entry($0) { print tool($0) }
  ' "$1"
}

# mise_cfg_extra <file> <base>...: the [tools] lines of <file> declaring a
# tool that none of the <base> files declares, as they are written.
mise_cfg_extra() {
  local file="$1" b bases=()
  shift
  for b in "$@"; do [ -f "$b" ] && bases+=("$b"); done
  [ -f "$file" ] || return 0
  awk -v q="'" -v target=$(( ${#bases[@]} + 1 )) "$_MISE_CFG_AWK"'
    FILENAME != cur { cur = FILENAME; n++; s = 0 }
    is_header($0) { s = is_tools($0); next }
    n < target && s && is_entry($0) { known[tool($0)] = 1; next }
    n == target && s && is_entry($0) && !(tool($0) in known) { print }
  ' "${bases[@]}" "$file"
}

# mise_cfg_strip <file> <base>: <file> without the lines mise_cfg_extra finds.
mise_cfg_strip() {
  awk -v q="'" "$_MISE_CFG_AWK"'
    FILENAME != cur { cur = FILENAME; n++; s = 0 }
    is_header($0) { s = is_tools($0); if (n == 2) print; next }
    n == 1 { if (s && is_entry($0)) known[tool($0)] = 1; next }
    s && is_entry($0) && !(tool($0) in known) { next }
    { print }
  ' "$2" "$1"
}

# mise_cfg_only_added <file> <base>: true when <file> is <base> plus added
# [tools] lines, and nothing else changed.
mise_cfg_only_added() {
  [ -f "$1" ] && [ -f "$2" ] || return 1
  cmp -s <(mise_cfg_strip "$1" "$2") "$2"
}

# mise_cfg_merge <shipped> <extra lines>: the shipped file with the given
# [tools] lines inserted after its last [tools] entry (after the [tools]
# header when it has none, in a new [tools] at the end when it has no such
# table). Taking these lines out again gives the shipped file back, byte for
# byte, which is what keeps the result "untouched" for the next seed.
mise_cfg_merge() {
  if [ -z "$2" ]; then
    cat "$1"
    return 0
  fi
  MISE_CFG_ADD="$2" awk -v q="'" "$_MISE_CFG_AWK"'
    NR == FNR {
      if (is_header($0)) { s = is_tools($0); if (s) { seen = 1; at = FNR } }
      else if (s && is_entry($0)) at = FNR
      next
    }
    { print }
    FNR == at { print ENVIRON["MISE_CFG_ADD"] }
    END { if (!seen) { print ""; print "[tools]"; print ENVIRON["MISE_CFG_ADD"] } }
  ' "$1" "$1"
}

# mise_cfg_names: the tool names of the entry lines read on stdin, on one
# line, comma separated.
mise_cfg_names() {
  awk -v q="'" "$_MISE_CFG_AWK"'
    is_entry($0) { printf "%s%s", (n++ ? ", " : ""), tool($0) }
    END { if (n) print "" }
  '
}
