#!/usr/bin/env bash
set -Eeuo pipefail

# Run before the files module, which overlays our non-focusing window types.
# Keep the plugin ID so existing DMS settings and the DankBar widget survive.
revision=85820f16252afcc74361117879764d735c97ef1b
# Optional destination is useful for validating the pinned payload outside an image.
destination=${1:-/usr/share/nirigo/dms-plugins/VirtualKeyboard}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
git init --quiet "$work"
git -C "$work" fetch --quiet --depth=1 https://github.com/sitolam/dms-plugins.git "$revision"
git -C "$work" checkout --quiet --detach FETCH_HEAD
[[ $(git -C "$work" rev-parse HEAD) == "$revision" ]]
install -d "$destination"
cp -a "$work/plugins/virtualkeyboard/." "$destination/"
install -m 0644 "$work/LICENSE" "$destination/LICENSE"
printf '%s\n' "$revision" >"$destination/UPSTREAM_REVISION"
