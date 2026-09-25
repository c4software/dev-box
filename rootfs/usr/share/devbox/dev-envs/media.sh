# shellcheck shell=bash
# devbox dev-env media: sourced by dev-box-dev-env, see /usr/share/devbox/lib/dev-env.sh.

details() {
  cat <<'TXT'
ffmpeg + yt-dlp + image optimizers and metadata tools (mise and devbox pkg)

Fetch, convert and inspect audio, video and pictures. Through mise, updated by
`devbox update tools`: yt-dlp (it breaks whenever a site changes, the release
of the week matters) and oxipng (lossless PNG). Through `devbox pkg`, put back
after a rebuild: ffmpeg and ffprobe (the mise registry only builds them from
source), pngquant (lossy PNG), jpegoptim, cwebp and dwebp (libwebp-utils),
exiftool (read or strip EXIF and GPS), mediainfo and aria2 (yt-dlp
--downloader aria2c). The image already has imagemagick and resvg for the
other conversions. With ffmpeg there, yazi shows video thumbnails. yt-dlp
wants a JavaScript runtime for YouTube: devbox dev-env deno. A removal takes all of it out, ffmpeg included, and
leaves ~/.config/yt-dlp and ~/.cache/yt-dlp in place.
TXT
}

# Functions rather than arrays: a file runs nothing at the top level.
media_tools() { echo yt-dlp oxipng; }
media_packages() { echo ffmpeg pngquant jpegoptim libwebp-utils perl-image-exiftool mediainfo aria2; }

is_installed() { declared yt-dlp && command -v ffmpeg >/dev/null 2>&1; }

install() {
  local tools packages
  read -ra tools <<<"$(media_tools)"
  read -ra packages <<<"$(media_packages)"
  dev-box-pkg add "${packages[@]}"
  mise use -g "${tools[@]/%/@latest}"
  log "ffmpeg $(ffmpeg -hide_banner -version | awk 'NR == 1 {print $3}'), yt-dlp $(mise x yt-dlp -- yt-dlp --version)"
  if ! declared deno; then
    log "YouTube needs a JavaScript runtime for yt-dlp: devbox dev-env deno"
  fi
  log "media is ready: yt-dlp <url>, ffmpeg -i in.mov out.mp4, oxipng -o 4 *.png, exiftool -all= photo.jpg"
}

uninstall() {
  local tools packages
  read -ra tools <<<"$(media_tools)"
  read -ra packages <<<"$(media_packages)"
  unuse "${tools[@]}"
  dev-box-pkg drop "${packages[@]}"
  log "~/.config/yt-dlp and ~/.cache/yt-dlp are left in place."
  log "video thumbnails in yazi need ffmpeg: devbox pkg add ffmpeg brings it back alone."
}
