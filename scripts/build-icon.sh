#!/bin/zsh
set -eu
cd "${0:A:h}/.."
iconset=".build/brand/Act.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/Brand/Act.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" Resources/Brand/Act.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/Act.icns
