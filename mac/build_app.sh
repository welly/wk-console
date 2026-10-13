#!/bin/sh
# Build a universal (Apple silicon + Intel) "WK Console.app" into mac/build/.
# Needs only the Xcode command line tools. With --zip, also makes the release zip.
# The app icon is pre-built in Resources/AppIcon.icns (see tools/make_icon.swift).
set -eu
cd "$(dirname "$0")"

VERSION=1.0.2
BUILD_NUMBER=3

# Build each architecture separately, then combine them: multi-arch builds in one
# go need the full Xcode app.
BINS=""
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx15.0"
    BINS="$BINS $(swift build -c release --triple "$ARCH-apple-macosx15.0" --show-bin-path)/WKConsole"
done
BIN=build/WKConsole-universal
mkdir -p build
# shellcheck disable=SC2086
lipo -create $BINS -output "$BIN"

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
    <string>__VERSION__</string>
    <key>CFBundleVersion</key>
    <string>__BUILD_NUMBER__</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>
    <string>For K1EL WinKeyer</string>
</dict>
</plist>
EOF

sed -i '' -e "s/__VERSION__/$VERSION/" -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/" "$APP/Contents/Info.plist"
rm "$BIN"

codesign --force --sign - "$APP"
echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/WKConsole"))"

if [ "${1:-}" = "--zip" ]; then
    ZIP="build/WK-Console-$VERSION.zip"
    rm -f "$ZIP"
    # ditto keeps the code signature and extended attributes intact.
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Zipped $ZIP"
fi
