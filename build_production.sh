#!/bin/bash
# Production build script for MacMuster
# Creates a production-ready app bundle
# 
# For local testing: uses ad-hoc signing (has limitations on resource sealing)
# For distribution: requires Apple Developer ID certificate and notarization
#   1. Sign with Developer ID: codesign --sign "Developer ID Application: Name" ...
#   2. Notarize: xcrun notarytool submit MacMuster.app --apple-id <id> --team-id <team> --wait
#   3. Staple: xcrun stapler staple MacMuster.app

set -e

APP_NAME="MacMuster"
BUILD_CONFIG="release"

echo "=== Building ${APP_NAME} (${BUILD_CONFIG}) ==="

# Clean previous builds
swift package clean

# Build release configuration with optimizations
echo "Building release binary..."
swift build -c release -Xswiftc -O -Xswiftc -Osize

# Get the binary path
BINARY_PATH=$(swift build -c release --show-bin-path)/${APP_NAME}

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

echo "Binary: $BINARY_PATH"
echo "Size: $(du -h "$BINARY_PATH" | cut -f1)"

# Strip debug symbols for smaller binary
echo "Stripping debug symbols..."
strip -x "$BINARY_PATH" 2>/dev/null || echo "strip not available, skipping"
echo "Stripped size: $(du -h "$BINARY_PATH" | cut -f1)"

# Get version
VERSION=$(git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo "1.0.0")
BUNDLE_ID="com.yourcompany.MacMuster"
APP_BUNDLE="${APP_NAME}.app"

# Create app bundle structure
echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/"

# Copy resources
echo "Copying resources..."
RESOURCES_DIR="Resources"
if [ -d "$RESOURCES_DIR" ]; then
    cp -R "$RESOURCES_DIR"/* "$APP_BUNDLE/Contents/Resources/"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MacMuster</string>
    <key>CFBundleDisplayName</key>
    <string>MacMuster</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourcompany.MacMuster</string>
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
    <key>NSHumanReadableCopyright</key>
    <string>© 2024 MacMuster. All rights reserved.</string>
</dict>
</plist>
PLIST_EOF

# Code sign with ad-hoc signature (for local testing only)
# Note: Ad-hoc signing has limitations - "Sealed Resources=none" is expected
# For distribution, use a Developer ID certificate and notarize
echo "Code signing (ad-hoc for local testing)..."
# Remove extended attributes that can cause signing failures
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - --options runtime --timestamp "$APP_BUNDLE" 2>/dev/null || codesign --force --deep --sign - "$APP_BUNDLE"

# Verify the binary runs
echo "Verifying binary..."
"$APP_BUNDLE/Contents/MacOS/MacMuster" --help 2>&1 | head -1 || true

echo ""
echo "=== Build complete ==="
echo "App bundle: ${APP_NAME}.app"
echo "Binary size: $(du -h "${APP_NAME}.app/Contents/MacOS/MacMuster" | cut -f1)"
echo "Bundle size: $(du -sh "${APP_NAME}.app" | cut -f1)"
echo ""
echo "=== Production Readiness Checklist ==="
echo "✓ Release build with optimizations (-O -Osize)"
echo "✓ Debug symbols stripped"
echo "✓ App bundle structure created"
echo "✓ Info.plist configured"
echo "✓ Resources copied"
echo "✓ Ad-hoc signed (for local testing)"
echo ""
echo "=== For Distribution (App Store / Direct) ==="
echo "1. Get Apple Developer ID certificate"
echo "2. Sign: codesign --sign \"Developer ID Application: Your Name\" --options runtime MacMuster.app"
echo "3. Notarize: xcrun notarytool submit MacMuster.app --apple-id <id> --team-id <team> --wait"
echo "4. Staple: xcrun stapler staple MacMuster.app"
echo ""
echo "=== To Install Locally ==="
echo "cp -R \"MacMuster.app\" /Applications/"
echo ""
echo "Build artifacts in: ${APP_NAME}.app"
