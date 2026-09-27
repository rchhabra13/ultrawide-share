#!/bin/zsh
# Builds UltrawideShare.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

APP=UltrawideShare.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  UltrawideShare.swift -o "$APP/Contents/MacOS/UltrawideShare"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.rishi.UltrawideShare</string>
  <key>CFBundleName</key><string>UltrawideShare</string>
  <key>CFBundleExecutable</key><string>UltrawideShare</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad hoc signing so macOS can remember the Screen Recording permission.
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
