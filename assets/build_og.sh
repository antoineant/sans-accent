#!/bin/bash
# Renders the share images site/assets/og-fr.png and og-en.png from og-card.html (needs Google Chrome).
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
cp ../site/assets/icon-512.png .
for lang in fr en; do
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1200,630 --virtual-time-budget=5000 \
        --screenshot="$(pwd)/../site/assets/og-$lang.png" "file://$(pwd)/og-card.html?lang=$lang" 2>/dev/null
done
rm icon-512.png
echo "Wrote site/assets/og-fr.png and og-en.png"
