#!/bin/zsh
# Builds build/FMF.app.
#
# Optional:
#   Config/backend.env  -> FMF_BACKEND_URL / FMF_BACKEND_KEY (Supabase URL + publishable key)
#   vendor/bin/         -> yt-dlp and ffmpeg binaries to bundle inside the app
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${FMF_VERSION:-1.0.0}"
BUILD_NUMBER="${FMF_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
FMF_BACKEND_URL="" FMF_BACKEND_KEY=""
[[ -f Config/backend.env ]] && source Config/backend.env

scripts/compile.sh

APP=build/FMF.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/FMF "$APP/Contents/MacOS/FMF"
cp legal/TERMS.md "$APP/Contents/Resources/Terms.md"

# App icon, rendered from the same SwiftUI logo the app uses.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
build/FMF --render-icon build/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z $size $size build/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double build/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if [[ -d vendor/bin ]]; then
  mkdir -p "$APP/Contents/Resources/bin"
  cp vendor/bin/* "$APP/Contents/Resources/bin/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FMF</string>
  <key>CFBundleDisplayName</key><string>FMF</string>
  <key>CFBundleIdentifier</key><string>org.freemusicfoundation.fmf</string>
  <key>CFBundleExecutable</key><string>FMF</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Free Music Foundation</string>
  <key>FMFBackendURL</key><string>${FMF_BACKEND_URL}</string>
  <key>FMFBackendKey</key><string>${FMF_BACKEND_KEY}</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
