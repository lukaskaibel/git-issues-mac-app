#!/bin/bash
# Makes one of the drawn variants the app icon:  Tools/set-icon.sh A   (or B, C, D)
set -euo pipefail
cd "$(dirname "$0")/.."
source=$(ls Design/icon-variants/icon-"$1"-*.png)
set_dir=GitIssues/Assets.xcassets/AppIcon.appiconset
for spec in "16:icon_16.png" "32:icon_16@2x.png" "32:icon_32.png" "64:icon_32@2x.png" "128:icon_128.png" \
            "256:icon_128@2x.png" "256:icon_256.png" "512:icon_256@2x.png" "512:icon_512.png" "1024:icon_512@2x.png"; do
  sips -z "${spec%%:*}" "${spec%%:*}" "$source" --out "$set_dir/${spec##*:}" >/dev/null
done
sips -z 256 256 "$source" --out Design/icon.png >/dev/null
echo "App icon set to variant $1."
