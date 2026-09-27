# shellcheck shell=bash
# devbox dev-env gpu: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.
# An alias of `devbox gpu install`, hidden from the menu and the list: it
# keeps DEV_ENVS=gpu working, which setup.sh writes when the GPU is asked for.

details() {
  cat <<'TXT'
The drivers of the host GPU: an alias of devbox gpu install

Kept so that DEV_ENVS=gpu installs the drivers at start. Everything about the
GPU lives in devbox gpu: its state, install, remove and a hardware encoding
test.
TXT
}

is_hidden() { return 0; }

is_supported() {
  local n
  for n in /dev/dri/renderD*; do
    [ -c "$n" ] && return 0
  done
  echo "no GPU in the box: add /dev/dri to the devices of compose.override.yaml on the host, then restart the container"
  return 1
}

is_installed() { command -v vainfo >/dev/null 2>&1; }

install() { dev-box-gpu install; }

uninstall() { dev-box-gpu remove; }
