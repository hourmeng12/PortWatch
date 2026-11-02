#!/bin/bash
# Builds a universal PortWatch.app, then PortWatch-<version>.dmg, .zip and SHA256SUMS.txt in dist/.
# Usage: scripts/release.sh 1.0.0
set -euo pipefail
VERSION=${1:?usage: scripts/release.sh <version>}
cd "$(dirname "$0")/.."
DIST=dist
APP=$DIST/PortWatch.app
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/PortWatch" "$APP/Contents/MacOS/"

# Liquid Glass app icon from the Icon Composer file (actool also writes an .icns fallback for older macOS).
xcrun actool Assets/AppIcon.icon --compile "$APP/Contents/Resources" --app-icon AppIcon \
  --platform macosx --minimum-deployment-target 15.0 --output-partial-info-plist "$DIST/icon.plist" >/dev/null
rm "$DIST/icon.plist"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PortWatch</string>
  <key>CFBundleDisplayName</key><string>PortWatch</string>
  <key>CFBundleIdentifier</key><string>io.github.hourmeng12.PortWatch</string>
  <key>CFBundleExecutable</key><string>PortWatch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Hourmeng Khy</string>
</dict>
</plist>
PLIST

# shortcut: ad-hoc signed, not notarized, so Gatekeeper asks on first open; sign with a Developer ID + notarytool to drop that.
codesign --force --sign - "$APP"

STAGE=$DIST/dmg
mkdir "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "PortWatch $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DIST/PortWatch-$VERSION.dmg" >/dev/null
rm -r "$STAGE"

ditto -c -k --keepParent "$APP" "$DIST/PortWatch-$VERSION.zip"
(cd "$DIST" && shasum -a 256 "PortWatch-$VERSION.dmg" "PortWatch-$VERSION.zip" > SHA256SUMS.txt)
ls -lh "$DIST"
