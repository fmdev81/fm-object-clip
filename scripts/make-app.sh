#!/bin/zsh
# Builds the release binaries and wraps them in an app bundle with an ad hoc signature: build/FMObjectClip.app
# The command-line tool goes into the bundle (Contents/MacOS/fm-object-clip-cli) and into build/bin/.
# Usage: scripts/make-app.sh   (from any folder)
set -euo pipefail
cd "${0:A:h}/.."
version=1.1
[ -f Resources/AppIcon.icns ] || scripts/make-icon.sh
swift build -c release --product FMObjectClip
swift build -c release --product fm-object-clip-cli
bin=$(swift build -c release --show-bin-path)
app=build/FMObjectClip.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/FMObjectClip" "$app/Contents/MacOS/FMObjectClip"
# SwiftPM writes the deployment target (13.0) as the SDK version. macOS then draws the app in the old style.
# Write the real SDK version, so that macOS 26 and later use Liquid Glass. Then sign the binary again (ad hoc),
# because Apple silicon runs only signed code. The bundle has no Developer ID signature.
sdk=$(xcrun --sdk macosx --show-sdk-version)
vtool -set-build-version macos 13.0 "$sdk" -replace -output "$app/Contents/MacOS/FMObjectClip" "$app/Contents/MacOS/FMObjectClip"
codesign --force --sign - "$app/Contents/MacOS/FMObjectClip"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>FMObjectClip</string>
  <key>CFBundleIdentifier</key><string>com.solutionscay.fm-object-clip</string>
  <key>CFBundleName</key><string>FMObjectClip</string>
  <key>CFBundleDisplayName</key><string>fm-object-clip</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" >/dev/null
# The command-line tool: in the bundle and in build/bin/.
cp "$bin/fm-object-clip-cli" "$app/Contents/MacOS/fm-object-clip-cli"
mkdir -p build/bin
cp "$bin/fm-object-clip-cli" build/bin/fm-object-clip-cli
echo "app: ${PWD}/$app"
echo "cli: ${PWD}/build/bin/fm-object-clip-cli"
echo "cli: ${PWD}/$app/Contents/MacOS/fm-object-clip-cli"
