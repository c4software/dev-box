# shellcheck shell=bash
# dev-box: the language the box speaks, for the few texts that have a
# translation (the devbox menu and the motd tips). Sourced, not run, by devbox
# and dev-box-motd. Pure bash, no fork: the motd is on the path of every login.
#
#   devbox_lang   sets DEVBOX_LANG to the language code of the locale (fr for
#                 fr_FR.UTF-8), empty when there is nothing to translate
#
# The locale is the first one set of LC_ALL, LC_MESSAGES and LANG, the order
# the C library itself follows. C, POSIX, C.UTF-8 and English give an empty
# code: English is the source text, and the fallback of every translation.
# LANG comes from .env, through /etc/devbox/env.

# shellcheck disable=SC2034 # DEVBOX_LANG is read by the scripts sourcing this
devbox_lang() {
  local loc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  loc="${loc%%.*}"
  loc="${loc%%@*}"
  loc="${loc%%_*}"
  loc="${loc,,}"
  case "$loc" in
    "" | c | posix | en) DEVBOX_LANG="" ;;
    [a-z][a-z] | [a-z][a-z][a-z]) DEVBOX_LANG="$loc" ;;
    *) DEVBOX_LANG="" ;;
  esac
}
