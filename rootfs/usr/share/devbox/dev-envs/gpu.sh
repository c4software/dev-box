# shellcheck shell=bash
# devbox dev-env gpu: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
Hardware acceleration: VA-API and Vulkan drivers for the host GPU (devbox pkg)

Needs the GPU of the host in the box: /dev/dri in the devices of
compose.override.yaml, then a restart of the container (the entrypoint adds
the user to the group that owns it). Installs through `devbox pkg`, put back
after a rebuild, the drivers of the GPU found there: intel-media-driver and
vulkan-intel on Intel, vulkan-radeon on AMD, and on every GPU vainfo
(libva-utils) and vulkaninfo (vulkan-tools) to check the result; mesa, with
the VA-API drivers of AMD and the others, comes as their dependency. ffmpeg then encodes and
decodes on the GPU (-hwaccel vaapi), OpenGL and Vulkan run on it. NVIDIA is
not offered: its GPU goes through the NVIDIA Container Toolkit, not
/dev/dri. A removal takes the drivers and the tools out, mesa with them
unless another package (chromium, ffmpeg) needs it.
TXT
}

# The render node the box sees, empty when compose.override.yaml passes none.
render_node() {
  local n
  for n in /dev/dri/renderD*; do
    [ -c "$n" ] && { echo "$n"; return 0; }
  done
  return 1
}

# The kernel driver behind the render node: i915 or xe (Intel), amdgpu or
# radeon (AMD), v3d, panfrost...
gpu_driver() {
  local node
  node="$(render_node)" || return 1
  basename "$(readlink -f "/sys/class/drm/${node##*/}/device/driver" 2>/dev/null)" 2>/dev/null
}

# Functions rather than arrays: a file runs nothing at the top level.
gpu_packages() {
  case "$(gpu_driver)" in
    i915|xe) echo libva-utils vulkan-tools intel-media-driver vulkan-intel ;;
    amdgpu|radeon) echo libva-utils vulkan-tools vulkan-radeon ;;
    *) echo libva-utils vulkan-tools ;;
  esac
}
all_gpu_packages() { echo libva-utils vulkan-tools intel-media-driver vulkan-intel vulkan-radeon; }

is_supported() {
  render_node >/dev/null && return 0
  echo "no GPU in the box: add /dev/dri to the devices of compose.override.yaml on the host, then restart the container"
  return 1
}

is_installed() { command -v vainfo >/dev/null 2>&1; }

install() {
  local node driver packages
  node="$(render_node)"
  driver="$(gpu_driver || true)"
  read -ra packages <<<"$(gpu_packages)"
  log "GPU: $node, kernel driver ${driver:-unknown}"
  dev-box-pkg add "${packages[@]}"
  if [ ! -r "$node" ] || [ ! -w "$node" ]; then
    log "⚠ $node is not readable by $(id -un): restart the container, the entrypoint adds you to its group"
    return 0
  fi
  if vainfo --display drm --device "$node" >/dev/null 2>&1; then
    log "VA-API: $(vainfo --display drm --device "$node" 2>/dev/null | sed -n 's/^.*Driver version: //p' | head -n 1)"
  else
    log "⚠ vainfo finds no VA-API driver for this GPU: vainfo --display drm --device $node says why"
  fi
  log "gpu is ready: vainfo --display drm --device $node"
  log "  ffmpeg -hwaccel vaapi -hwaccel_device $node -hwaccel_output_format vaapi -i in.mp4 -c:v h264_vaapi out.mp4"
}

uninstall() {
  local packages
  read -ra packages <<<"$(all_gpu_packages)"
  dev-box-pkg drop "${packages[@]}"
}
