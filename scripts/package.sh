#!/bin/zsh
# Builds the app and packages it for download:
#   dist/Resonance-Studio-<version>.dmg  open it, drag the app into Applications
#   dist/Resonance-Studio-<version>.zip  double-click to unzip, drag into Applications
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${RESONANCE_VERSION:-1.0.0}"
export RESONANCE_VERSION="$VERSION"
scripts/build-app.sh

APP="build/Resonance Studio.app"
NAME="Resonance-Studio-$VERSION"
rm -rf dist build/dmg
mkdir -p dist build/dmg

# Zip: keeps the .app bundle, its signature and permissions intact.
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$NAME.zip"

# Disk image: the app next to a shortcut to Applications, so installing is one drag.
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -quiet -volname "Resonance Studio" -srcfolder build/dmg -fs HFS+ -format UDZO -ov "dist/$NAME.dmg"
rm -rf build/dmg

(cd dist && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt)
ls -lh dist
