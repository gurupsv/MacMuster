#!/bin/sh

for variant in Light Dark; do
  src="MacMusterIcon${variant}.png"
  dest="MacMusterIcon${variant}.iconset"
  mkdir -p "$dest"

  sips -z 16 16     "$src" --out "$dest/icon_16x16.png"
  sips -z 32 32     "$src" --out "$dest/icon_16x16@2x.png"
  sips -z 32 32     "$src" --out "$dest/icon_32x32.png"
  sips -z 64 64     "$src" --out "$dest/icon_32x32@2x.png"
  sips -z 128 128   "$src" --out "$dest/icon_128x128.png"
  sips -z 256 256   "$src" --out "$dest/icon_128x128@2x.png"
  sips -z 256 256   "$src" --out "$dest/icon_256x256.png"
  sips -z 512 512   "$src" --out "$dest/icon_256x256@2x.png"
  sips -z 512 512   "$src" --out "$dest/icon_512x512.png"
  sips -z 1024 1024 "$src" --out "$dest/icon_512x512@2x.png"
done
