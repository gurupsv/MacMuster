#!/bin/bash
# Quick local dev build for MacMuster.
# Uses the same bundle ID and signing approach as build_production.sh.
# For distribution (Developer ID + notarization) use build_production.sh instead.

set -e

APP_NAME="MacMuster"
APP_DIR="${APP_NAME}.app"
BUNDLE_ID="com.macmuster.app"
ENTITLEMENTS="entitlements.plist"

# Build release binary (debug builds can mask performance issues)
echo "Building ${APP_NAME}..."
swift build -c release

BIN_DIR=$(swift build -c release --show-bin-path)
BINARY="${BIN_DIR}/${APP_NAME}"

if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found at $BINARY"
    exit 1
fi

# (Re)create the bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/"

# Copy resources
RESOURCES_DIR="Resources"
if [ -d "$RESOURCES_DIR" ]; then
    cp -R "$RESOURCES_DIR"/* "$APP_DIR/Contents/Resources/"
fi

# Write Info.plist (must match build_production.sh for stable bundle identity)
cat > "$APP_DIR/Contents/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MacMuster</string>
    <key>CFBundleDisplayName</key>
    <string>MacMuster</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>MacMuster</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>MacAppIcon</string>
    <key>CFBundleIconName</key>
    <string>MacAppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST_EOF

# Code sign — apply entitlements so TCC behaviour matches what is documented
echo "Code signing..."
xattr -cr "$APP_DIR"

if [ -n "$DEVELOPER_ID" ]; then
    codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" "$APP_DIR"
else
    # Ad-hoc for local testing (no stable cdhash, so TCC grants don't persist)
    if [ -f "$ENTITLEMENTS" ]; then
        codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_DIR"
    else
        codesign --force --sign - "$APP_DIR"
    fi
fi

echo ""
echo "App bundle created: ${APP_DIR}"
echo "Bundle size: $(du -sh "${APP_DIR}" | cut -f1)"
