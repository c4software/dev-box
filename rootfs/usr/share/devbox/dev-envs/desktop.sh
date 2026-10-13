# shellcheck shell=bash
# devbox dev-env desktop: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
A graphical session reached with gliff, started at connection

For a browser, or any window, of the box on your screen. gliff shows a
Hyprland session through the ssh connection you already have: no port, no
account. The environment brings Hyprland, labwc (Hyprland does not start
without a screen, so it runs inside a labwc that has none), foot as the
terminal, swaybg for the background, fuzzel as the application launcher,
noto-fonts-emoji so that emojis are drawn and libva, through `devbox pkg`, and
gliff-server as a mise tool (http:gliff, the package of the Omarchy
repository, pinned with its sha256, nothing on the PATH). Nothing runs once
it is installed: the session starts when a gliff client connects, on a
private screen sized to its window, and then stays, with what is open in it,
until `devbox desktop stop`: nothing stops it on its own. Once installed,
`devbox desktop` joins the menu of devbox: the state, start and stop, and
the graphical apps to install in it (VS Code, Chromium), which are not part
of the environment. It needs
the GPU of the host in the box (devbox help gpu): Hyprland refuses to start
without one. About 350 MB of packages, and 290 MB of memory while the
session is on. linux x86_64 only, the one it was tried on. A removal takes out
gliff-server and the packages, and leaves the apps and
~/.config/dev-box/desktop in place. The steps on your machine: devbox help
desktop.
TXT
}

GLIFF="http:gliff"
GLIFF_VERSION="0.3.1"
GLIFF_URL="https://pkgs.omarchy.org/edge/x86_64/gliff-0.3.1-1-x86_64.pkg.tar.zst"
GLIFF_SHA256="73887d4f2e040e7c3a9524ca2aeeac3a5983aa27bbf825ff2027b9ec7bbe3782"
# noto-fonts-emoji: without it no font of the box has an emoji, and the
# terminal and every app draw a square in its place.
PACKAGES=(hyprland labwc foot swaybg fuzzel noto-fonts-emoji libva)

is_installed() { declared "$GLIFF" && command -v Hyprland >/dev/null 2>&1 && command -v labwc >/dev/null 2>&1; }

is_supported() {
  if [ "$(uname -m)" != "x86_64" ]; then
    echo "it has only been tried on x86_64"
    return 1
  fi
  ls /dev/dri/renderD* >/dev/null 2>&1 && return 0
  echo "Hyprland needs the GPU of the host, and the box has none: devbox help gpu"
  return 1
}

install() {
  dev-box-pkg add "${PACKAGES[@]}"
  # bin_path names a directory without a command: gliff-server stays the
  # launcher of the image (/usr/local/bin/gliff-server), which starts the
  # session before it hands over to this one.
  mise use -g "${GLIFF}[url=$GLIFF_URL,checksum=sha256:$GLIFF_SHA256,bin_path=share]@$GLIFF_VERSION"
  log "$("$(mise where "$GLIFF")/usr/bin/gliff-server" --version 2>&1 | head -n 1), $(Hyprland --version 2>&1 | head -n 1 | cut -d' ' -f1-2)"
  log "desktop is ready and off: it starts when a gliff client connects, and stops with devbox desktop stop."
  log "from your machine: gliff --headless $(id -un)@$(uname -n)"
  log "devbox desktop is now in the menu of devbox: start, stop, and the apps (VS Code, Chromium)"
  log "the steps, the keys and the mobile client: devbox help desktop"
}

uninstall() {
  dev-box-desktop stop >/dev/null 2>&1 || true
  unuse "$GLIFF"
  dev-box-pkg drop "${PACKAGES[@]}"
  log "the apps of devbox desktop install and ~/.config/dev-box/desktop are left in place."
}
