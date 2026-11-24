#!/bin/zsh
# Makes Resources/AppIcon.icns from scripts/make-icon.swift, with sips and iconutil.
set -euo pipefail
cd "${0:A:h}/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swift scripts/make-icon.swift "$tmp/icon-1024.png" >/dev/null
set=$tmp/AppIcon.iconset
mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s "$tmp/icon-1024.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$tmp/icon-1024.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$set" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns"
