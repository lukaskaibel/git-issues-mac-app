#!/bin/bash
# Renders the Icon Composer documents into the PNGs the app offers in Settings and the README shows.
#   swift Tools/make-card-icon.swift && Tools/render-icons.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
resources=Packages/GitIssuesKit/Sources/GitIssuesKit/Resources
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# render <document> <rendition> <output>: the icon at Dock proportions, an 824 px body on a 1024 px canvas.
render() {
  "$ictool" "$1" --export-image --output-file "$work/full.png" --platform macOS --rendition "$2" \
    --width 1024 --height 1024 --scale 1 >/dev/null
  swift Tools/pad-icon.swift "$work/full.png" "$3"
}

render GitIssues/AppIcon.icon Default "$work/light.png"
render GitIssues/AppIcon.icon Dark "$work/dark.png"
render Design/AppIcon-Violet.icon Default "$work/violet.png"
swift Tools/pad-icon.swift --split "$work/light.png" "$work/dark.png" "$work/auto.png"

for name in light dark violet auto; do
  sips -z 512 512 "$work/$name.png" --out "$resources/icon-A-$name.png" >/dev/null
done
sips -z 256 256 "$work/light.png" --out Design/icon.png >/dev/null
sips -z 256 256 "$work/dark.png" --out Design/icon-dark.png >/dev/null
echo "Rendered the card icons into $resources and Design/."
