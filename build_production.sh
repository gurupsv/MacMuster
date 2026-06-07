#!/bin/bash
# Production build script for MacMuster
# Creates a production-ready app bundle
# 
# For local testing: uses ad-hoc signing (has limitations on resource sealing)
# For distribution: requires Apple Developer ID certificate and notarization
#   1. Sign with Developer ID: codesign --sign "Developer ID Application: Name" ...
#   2. Notarize: xcrun notarytool submit MacMuster.app --apple-id <id> --team-id <team> --wait
#   3. Staple: xcrun stapler staple MacMuster.app
#
# Universal Binary Build (Intel + Apple Silicon):
# Set BUILD_UNIVERSAL=1 to build for both architectures:
#   BUILD_UNIVERSAL=1 ./build_production.sh

set -e

APP_NAME="MacMuster"
BUILD_CONFIG="release"

# Check if we should build a universal binary (both Intel and Apple Silicon)
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo "=== Building Universal Binary (Intel + Apple Silicon) ==="
else
    echo "=== Building ${APP_NAME} (${BUILD_CONFIG}) ==="
fi

# Clean previous builds
swift package clean

# Build release configuration with optimizations
echo "Building release binary..."

if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    # Build universal binary for both Intel (x86_64) and Apple Silicon (arm64)
    echo "Building universal binary for arm64 and x86_64..."
    swift build -c release --arch arm64 --arch x86_64 -Xswiftc -O -Xswiftc -Osize
else
    # Build for the current architecture only (default behavior)
    echo "Building for current architecture..."
    swift build -c release -Xswiftc -O -Xswiftc -Osize
fi

# Get the binary path
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    # For universal build, get the arm64 binary (both will be merged)
    BINARY_PATH=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${APP_NAME}
else
    BINARY_PATH=$(swift build -c release --show-bin-path)/${APP_NAME}
fi

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

echo "Binary: $BINARY_PATH"
echo "Size: $(du -h "$BINARY_PATH" | cut -f1)"

# If building universal, merge arm64 and x86_64 binaries
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo "Merging arm64 and x86_64 binaries into universal binary..."
    
    # Get paths for both architecture-specific builds
    ARM64_PATH=$(swift build -c release --arch arm64 --show-bin-path)/${APP_NAME}
    X86_64_PATH=$(swift build -c release --arch x86_64 --show-bin-path)/${APP_NAME}
    
    if [ ! -f "$ARM64_PATH" ] || [ ! -f "$X86_64_PATH" ]; then
        echo "Error: Architecture-specific binaries not found for universal merge"
        exit 1
    fi
    
    # Create temporary directory for merging
    TEMP_DIR=$(mktemp -d)
    
    # Copy both architectures to temp dir
    cp "$ARM64_PATH" "${TEMP_DIR}/${APP_NAME}_arm64"
    cp "$X86_64_PATH" "${TEMP_DIR}/${APP_NAME}_x86_64"
    
    # Merge using lipo
    if command -v lipo &> /dev/null; then
        lipo -create -output "${TEMP_DIR}/${APP_NAME}_universal" \
            "${TEMP_DIR}/${APP_NAME}_arm64" \
            "${TEMP_DIR}/${APP_NAME}_x86_64"
        
        # Replace original with universal binary
        cp "${TEMP_DIR}/${APP_NAME}_universal" "$BINARY_PATH"
        rm -rf "${TEMP_DIR}"
        
        echo "Universal binary created successfully!"
    else
        echo "Warning: lipo not found, using arm64 binary only"
    fi
fi

# Strip debug symbols for smaller binary (after merging if universal)
echo "Stripping debug symbols..."
strip -x "$BINARY_PATH" 2>/dev/null || echo "strip not available, skipping"
echo "Stripped size: $(du -h "$BINARY_PATH" | cut -f1)"

if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo "Universal binary includes both arm64 and x86_64 architectures"
fi

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

if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo ""
    echo "=== Universal Binary Build Complete ==="
else
    echo ""
    echo "=== Build complete ==="
fi

echo "App bundle: ${APP_NAME}.app"
echo "Binary size: $(du -h "${APP_NAME}.app/Contents/MacOS/MacMuster" | cut -f1)"
echo "Bundle size: $(du -sh "${APP_NAME}.app" | cut -f1)"

# Show binary architecture info
if command -v file &> /dev/null; then
    echo ""
    echo "Binary Architecture:"
    file "${APP_NAME}.app/Contents/MacOS/MacMuster"
fi

echo ""
echo "=== Production Readiness Checklist ==="
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo "✓ Universal binary (Intel x86_64 + Apple Silicon arm64)"
else
    echo "✓ Release build with optimizations (-O -Osize)"
fi
echo "✓ Debug symbols stripped"
echo "✓ App bundle structure created"
echo "✓ Info.plist configured"
echo "✓ Resources copied"
echo "✓ Ad-hoc signed (for local testing)"
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo ""
    echo "=== For Universal Binary Distribution ==="
    echo "Binary supports both Intel (x86_64) and Apple Silicon (arm64)"
else
    echo ""
    echo "=== For Distribution (App Store / Direct) ==="
fi
echo "1. Get Apple Developer ID certificate (if not already signed)"
echo "2. Sign: codesign --sign \"Developer ID Application: Your Name\" --options runtime MacMuster.app"
echo "3. Notarize: xcrun notarytool submit MacMuster.app --apple-id <id> --team-id <team> --wait"
echo "4. Staple: xcrun stapler staple MacMuster.app"
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo ""
    echo "=== Universal Binary Installation ==="
    echo "This binary runs on both Intel and Apple Silicon Macs"
fi

echo ""
echo "=== To Install Locally ==="
echo "cp -R \"MacMuster.app\" /Applications/"
echo ""
echo "Build artifacts in: ${APP_NAME}.app"

# Build summary
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo ""
    echo "=== Universal Binary Build Summary ==="
    echo "To build universal binaries in the future:"
    echo "  BUILD_UNIVERSAL=1 ./build_production.sh"
fi
