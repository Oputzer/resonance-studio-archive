#!/bin/zsh
# Compiles the Resonance Studio executable into build/ResonanceStudio (universal).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/vfs
SDK="$(xcrun --show-sdk-path)"
OVERLAY=()
# Some Command Line Tools releases ship two module maps that both define
# SwiftBridging, which breaks every build. Hide the duplicate with a VFS overlay.
CLT_SWIFT=/Library/Developer/CommandLineTools/usr/include/swift
if [[ -f $CLT_SWIFT/module.modulemap && -f $CLT_SWIFT/bridging.modulemap ]]; then
  : > build/vfs/empty.modulemap
  cat > build/vfs/overlay.yaml <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "name": "$CLT_SWIFT", "type": "directory",
  "contents": [ { "name": "module.modulemap", "type": "file", "external-contents": "$PWD/build/vfs/empty.modulemap" } ] } ] }
YAML
  OVERLAY=(-vfsoverlay build/vfs/overlay.yaml -Xcc -ivfsoverlay -Xcc build/vfs/overlay.yaml)
fi
# Builds a universal binary (Apple silicon + Intel). Set ARCHS=arm64 for a faster local build.
ARCHS=(${=ARCHS:-arm64 x86_64})
SLICES=()
for arch in $ARCHS; do
  swiftc -O -parse-as-library -target $arch-apple-macos14.0 -sdk "$SDK" "${OVERLAY[@]}" \
    -module-name ResonanceStudio $(find Sources/ResonanceStudio -name '*.swift') -o build/ResonanceStudio-$arch
  SLICES+=(build/ResonanceStudio-$arch)
done
lipo -create "${SLICES[@]}" -output build/ResonanceStudio
rm -f "${SLICES[@]}"
