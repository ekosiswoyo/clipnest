#!/bin/zsh
set -eu
cd "${0:A:h}/.."
VERSION="$(cat VERSION)"
swift build -c release
APP="$PWD/build/ClipNest.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClipNest "$APP/Contents/MacOS/ClipNest"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClipNest</string>
<key>CFBundleIdentifier</key><string>dev.clipnest.app</string>
<key>CFBundleName</key><string>ClipNest</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
