# shellcheck shell=bash
# devbox dev-env browser: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Headless Chromium + fonts, page screenshots for an agent (devbox pkg)

The mise registry has no browser: playwright and agent-browser download a
Chromium built for Debian and Ubuntu, which needs libraries `playwright
install-deps` cannot install on Arch. The distribution package works as it is,
on amd64 and on Arch Linux ARM, so chromium and noto-fonts go through
`devbox pkg`, which puts them back after a rebuild. noto-fonts: without it
every emoji, symbol or non Latin script renders as a square. A removal leaves
~/.config/chromium and ~/.cache/chromium in place.
TXT
}

is_installed() { command -v chromium >/dev/null 2>&1; }

install() {
  dev-box-pkg add chromium noto-fonts
  log "chromium is ready, headless (no display in the box):"
  log "  chromium --headless --no-sandbox --disable-gpu --screenshot=/tmp/page.png http://localhost:3000"
  log "the devbox skill has the details: ~/.claude/skills/devbox/browser.md"
}

uninstall() {
  dev-box-pkg drop chromium noto-fonts
  log "~/.config/chromium and ~/.cache/chromium are left in place."
}
