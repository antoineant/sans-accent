#!/bin/bash
# Renders assets/AppIcon.icns (every size macOS needs) from make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")"
STYLE=tricolore
SET=AppIcon.iconset
rm -rf "$SET" && mkdir "$SET"
for n in 16 32 128 256 512; do
    swift make_icon.swift $STYLE "$SET/icon_${n}x${n}.png" $n
    swift make_icon.swift $STYLE "$SET/icon_${n}x${n}@2x.png" $((n * 2))
done
iconutil -c icns "$SET" -o AppIcon.icns
rm -rf "$SET"
echo "Wrote assets/AppIcon.icns"
