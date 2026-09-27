# shellcheck shell=bash
# devbox dev-env browser: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Headless Chromium + fonts + agent-browser, a browser a coding agent can drive

chromium and noto-fonts go through `devbox pkg`, which puts them back after a
rebuild: the builds Playwright and Puppeteer download target Debian and
Ubuntu, the distribution package works as it is, on amd64 and on Arch Linux
ARM. noto-fonts: without it every emoji, symbol or non Latin script renders
as a square. agent-browser comes through mise (a single binary, updated by
`devbox update tools`): a command line made for agents, open, snapshot,
click, fill, screenshot, eval, with no script and no npm install.
~/.agent-browser/config.json points it at the system Chromium, so it never
downloads one. A removal leaves ~/.config/chromium, ~/.cache/chromium and
~/.agent-browser in place.
TXT
}

CHROMIUM=/usr/bin/chromium
AB_CONFIG="$HOME/.agent-browser/config.json"

is_installed() { command -v chromium >/dev/null 2>&1 && declared agent-browser; }

# ~/.agent-browser/config.json: executablePath set to the system Chromium.
# Created when missing, completed when it has no executablePath, left alone
# when it names another browser.
point_at_chromium() {
  local current tmp
  mkdir -p "${AB_CONFIG%/*}"
  if [ ! -s "$AB_CONFIG" ]; then
    printf '{\n  "executablePath": "%s"\n}\n' "$CHROMIUM" > "$AB_CONFIG"
    log "agent-browser uses $CHROMIUM (~/.agent-browser/config.json)"
    return 0
  fi
  if ! current="$(jq -r '.executablePath // empty' "$AB_CONFIG" 2>/dev/null)"; then
    log "⚠ ~/.agent-browser/config.json is not valid JSON, left alone: set \"executablePath\": \"$CHROMIUM\" in it"
    return 0
  fi
  if [ -z "$current" ]; then
    tmp="$(mktemp)"
    jq --arg p "$CHROMIUM" '.executablePath = $p' "$AB_CONFIG" > "$tmp" && mv "$tmp" "$AB_CONFIG"
    log "agent-browser uses $CHROMIUM (added to ~/.agent-browser/config.json)"
  elif [ "$current" != "$CHROMIUM" ]; then
    log "~/.agent-browser/config.json names $current, left alone ($CHROMIUM is the system Chromium)"
  fi
}

install() {
  dev-box-pkg add chromium noto-fonts
  mise use -g agent-browser@latest
  point_at_chromium
  log "chromium and agent-browser are ready, headless (no display in the box):"
  log "  agent-browser open http://localhost:3000 && agent-browser snapshot && agent-browser screenshot /tmp/page.png"
  log "  chromium --headless --no-sandbox --disable-gpu --screenshot=/tmp/page.png http://localhost:3000"
  log "the devbox skill has the details: ~/.claude/skills/devbox/browser.md"
}

uninstall() {
  unuse agent-browser
  dev-box-pkg drop chromium noto-fonts
  log "~/.config/chromium, ~/.cache/chromium and ~/.agent-browser are left in place."
}
