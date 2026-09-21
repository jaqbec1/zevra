#!/bin/sh
# Build a universal, local-only preview without machine-specific provisioning.
set -eu
cd "$(dirname "$0")"
xcodebuild -quiet -project AttentionLog.xcodeproj -scheme AttentionLog \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/preview ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO ATTENTION_CLOUD_ENABLED=NO build
app=build/preview/Build/Products/Release/Zevra.app
codesign --force --sign - --options runtime "$app"
codesign --verify --deep --strict "$app"
mkdir -p build/artifacts
ditto -c -k --sequesterRsrc --keepParent "$app" build/artifacts/Zevra-macOS-universal.zip
(cd build/artifacts && shasum -a 256 Zevra-macOS-universal.zip > SHA256SUMS.txt)
