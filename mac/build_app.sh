#!/bin/sh
# Build "WK Console.app" into mac/build/. Needs only the Xcode command line tools.
# The app icon is pre-built in Resources/AppIcon.icns (see tools/make_icon.swift).
set -eu
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/WKConsole"

APP="build/WK Console.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WKConsole"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>WK Console</string>
    <key>CFBundleDisplayName</key>
    <string>WK Console</string>
    <key>CFBundleIdentifier</key>
    <string>local.wk-console</string>
    <key>CFBundleExecutable</key>
    <string>WKConsole</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>
    <string>For K1EL WinKeyer</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
