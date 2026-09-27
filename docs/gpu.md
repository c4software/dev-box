# GPU acceleration

The box can use the GPU of the host to decode and encode video (ffmpeg with
VA-API), and for OpenGL and Vulkan: Intel, AMD and the Raspberry Pi's, through
`/dev/dri`. Everything about it lives in one command, `devbox gpu`.

```bash
devbox gpu            # the state, and the next step when something is missing
devbox gpu install    # the drivers of the GPU found, through devbox pkg
devbox gpu test       # 10 s of 1080p encoded on the GPU, then on the CPU
devbox gpu remove     # take the drivers out again
```

`devbox status` sums it up on one line and points to `devbox gpu`.

## Passing the GPU to the box

The box sees no GPU until the host hands it over. The setup script asks when
the machine has a `/dev/dri`; otherwise, on the host, add it to
`compose.override.yaml` (the GPU block of `compose.override.example.yaml`)
and restart the container:

```yaml
services:
  dev-box:
    devices:
      - /dev/dri
```

With the podman block, `/dev/dri` goes in its `devices` list: a second
`devices` key is refused. A host without `/dev/dri` (Docker Desktop on macOS)
refuses to start the container with that line, which is why it stays out of
`compose.yaml`.

The nodes of `/dev/dri` belong to the `video` and `render` groups of the host,
whose GIDs mean nothing in the image. At every start the entrypoint adds the
user to the group that owns each node, created as `dri<gid>` when the image
has none with that GID: no `group_add` to write, the same override works on
any host. `docker logs dev-box` says which groups were added.

## Drivers

`devbox gpu install` picks the packages from the kernel driver of the GPU and
installs them through `devbox pkg`, so they come back after a rebuild:

| GPU | Packages |
| --- | --- |
| Intel (`i915`, `xe`) | `intel-media-driver`, `vulkan-intel` |
| AMD (`amdgpu`, `radeon`) | `vulkan-radeon` |
| every GPU | `libva-utils` (`vainfo`), `vulkan-tools` (`vulkaninfo`) |

`mesa`, which holds the VA-API drivers of AMD and the others, comes as their
dependency. `DEV_ENVS=gpu` in `.env` does the same at start (the setup script
writes it when the GPU is asked for); `devbox dev-env gpu` is kept as a
hidden alias for that.

## Checking and using it

`devbox gpu` shows the device and its kernel driver, whether your user can
open it, the VA-API driver with the codecs it decodes and encodes, and the
Vulkan device. `devbox gpu test` needs ffmpeg (`devbox dev-env media`): on an
Intel UHD 620 class iGPU, the GPU encodes the 10 s of 1080p in about 1.2 s
against 5 s for the CPU.

```bash
vainfo --display drm --device /dev/dri/renderD128   # the VA-API profiles
ffmpeg -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 \
  -hwaccel_output_format vaapi -i in.mp4 -c:v h264_vaapi out.mp4
```

## What does not use it

- **NVIDIA**: its GPU goes through the NVIDIA Container Toolkit, not
  `/dev/dri`; not covered.
- **Headless Chromium** (`devbox dev-env browser`): it renders in software
  (SwiftShader) even with the GPU and the drivers there, whatever the flags.
  Screenshots and DOM dumps do not need more.
