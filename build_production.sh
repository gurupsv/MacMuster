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
#
# Environment variables:
#   BUILD_UNIVERSAL=1   build arm64 + x86_64 and merge with lipo
#   SKIP_PKG=1          stop at the .app; do not build MacMuster.pkg
#   DEVELOPER_ID        "Developer ID Application: ..."  — signs the .app
#   INSTALLER_ID        "Developer ID Installer: ..."    — signs the .pkg (a different cert)
#   NOTARY_PROFILE      notarytool keychain profile; notarizes+staples whatever is signed

set -e

source "$(dirname "$0")/build_common.sh"

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

# Version, from the single source of truth.
#
# CFBundleShortVersionString is user-visible (Settings renders it verbatim) and Apple requires
# at most three period-separated integers. This used to be `git describe --tags --always --dirty`,
# which produces "1.0.1-dirty" — invalid, shown to users, and worse, sourced from the latest tag
# rather than version.txt, so this script and create_app_bundle.sh reported different versions
# for the same commit. When no tag existed it degraded further to a bare commit hash.
BASE_VERSION=$(cat version.txt 2>/dev/null || echo "1.0.0")
VERSION="${BASE_VERSION}"
BUILD_NUM=$(git rev-list --count HEAD 2>/dev/null || echo "1")

# Build provenance, recorded in its own Info.plist key so a crash report can still be traced to
# an exact tree without that detail leaking into the version users see.
GIT_REVISION=$(git describe --tags --always --dirty 2>/dev/null || echo "unknown")
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo ""
    echo "Warning: building from a dirty working tree (${GIT_REVISION})." >&2
    echo "         This build cannot be reproduced from a commit — commit or stash before releasing." >&2
    echo ""
fi
BUNDLE_ID="com.macmuster.app"
APP_BUNDLE="${APP_NAME}.app"

# Create app bundle structure
echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/"

# Copy resources (explicit list — see build_common.sh)
echo "Copying resources..."
copy_bundle_resources "$APP_BUNDLE/Contents/Resources"
compile_asset_catalog "$APP_BUNDLE/Contents/Resources"

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
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>MacMuster</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>MacMusterIconDark.icns</string>
    <key>CFBundleIconName</key>
    <string>MacMusterIconDark</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>MacMusterGitRevision</key>
    <string>${GIT_REVISION}</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2024 MacMuster. All rights reserved.</string>
</dict>
</plist>
PLIST_EOF

# Code sign with ad-hoc signature (for local testing only)
# Note: Ad-hoc signing has limitations - "Sealed Resources=none" is expected
# For distribution, use a Developer ID certificate and notarize
echo "Code signing..."
# Remove extended attributes that can cause signing failures
xattr -cr "$APP_BUNDLE"

# S2 FIX: Sign properly (not --deep, which is deprecated and breaks TCC across rebuilds).
# S1 FIX: Apply entitlements.plist so the documented trust model is actually enforced.
# For local testing: ad-hoc signing (identity "-").
# For distribution: sign with Developer ID (see instructions below).
ENTITLEMENTS="entitlements.plist"
if [ -n "$DEVELOPER_ID" ]; then
    # Production signing with Developer ID (set DEVELOPER_ID env var to sign for distribution)
    # --options runtime enables the Hardened Runtime, required for notarization.
    codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
    # Local ad-hoc signing (no stable cdhash, so TCC grants will not persist)
    if [ -f "$ENTITLEMENTS" ]; then
        codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
    else
        codesign --force --sign - "$APP_BUNDLE"
    fi
fi

# S3: Automated notarization + stapling.
# Only runs when both DEVELOPER_ID and NOTARY_PROFILE are set, so default local/ad-hoc
# builds are completely unaffected. NOTARY_PROFILE is a keychain profile created once via:
#   xcrun notarytool store-credentials "<profile-name>" --apple-id <id> --team-id <team> --password <app-specific-password>
if [ -n "$DEVELOPER_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo "Notarizing (profile: $NOTARY_PROFILE)..."
    NOTARY_ZIP="${APP_NAME}_notarize.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$NOTARY_ZIP"
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"
elif [ -n "$DEVELOPER_ID" ]; then
    echo "Skipping notarization: set NOTARY_PROFILE to a notarytool keychain profile to notarize+staple automatically."
fi

# ---------------------------------------------------------------------------
# Installer package
# ---------------------------------------------------------------------------
# Set SKIP_PKG=1 to stop at the .app.
#
# Signing an installer requires a *Developer ID Installer* certificate — a different
# certificate from the Developer ID Application one used for the app above. Set INSTALLER_ID
# to use it; without it the .pkg is unsigned and only good for local testing.
if [ "${SKIP_PKG:-0}" != "1" ]; then
    echo ""
    echo "=== Building installer package ==="

    PKG_PATH="${APP_NAME}.pkg"
    PKG_UNSIGNED="${APP_NAME}-unsigned.pkg"
    rm -f "$PKG_PATH" "$PKG_UNSIGNED"

    # Two things here are deliberate, because the previous hand-rolled package got both wrong:
    #   --install-location /Applications, not the build directory. That package was built with
    #     the source tree as its install location, so installing it dropped the app into the repo.
    #   --version "$BASE_VERSION", not "$VERSION". pkgbuild wants a plain dotted-numeric string;
    #     handing it the `git describe` value ("469f83c-dirty") is what silently produced the
    #     nonsense package version "469.0.0".
    pkgbuild \
        --component "$APP_BUNDLE" \
        --install-location /Applications \
        --identifier "$BUNDLE_ID" \
        --version "$BASE_VERSION" \
        "$PKG_UNSIGNED"

    if [ -n "$INSTALLER_ID" ]; then
        echo "Signing installer with: $INSTALLER_ID"
        productsign --sign "$INSTALLER_ID" "$PKG_UNSIGNED" "$PKG_PATH"
        rm -f "$PKG_UNSIGNED"
    else
        mv "$PKG_UNSIGNED" "$PKG_PATH"
        echo "Installer is unsigned — set INSTALLER_ID=\"Developer ID Installer: Your Name\" to sign it."
    fi

    # Gatekeeper validates the installer itself, so the .pkg needs its own notarization ticket
    # even though the app inside it already carries one. notarytool accepts a .pkg directly —
    # no zip wrapper, unlike the bare .app above.
    if [ -n "$INSTALLER_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
        echo "Notarizing installer (profile: $NOTARY_PROFILE)..."
        xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
        echo "Stapling installer..."
        xcrun stapler staple "$PKG_PATH"
    elif [ -n "$INSTALLER_ID" ]; then
        echo "Skipping installer notarization: set NOTARY_PROFILE to notarize+staple automatically."
    fi

    echo "Installer: ${PKG_PATH} ($(du -h "$PKG_PATH" | cut -f1))"
fi

# Verify the binary runs (non-blocking - launch app in background and terminate after timeout)
echo "Verifying binary..."
"$APP_BUNDLE/Contents/MacOS/MacMuster" &
APP_PID=$!
sleep 2
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true

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
if [ -n "$DEVELOPER_ID" ]; then
    echo "✓ Signed with Developer ID + Hardened Runtime ($DEVELOPER_ID)"
else
    echo "✓ Ad-hoc signed (for local testing only — not suitable for distribution)"
fi
if [ -n "$DEVELOPER_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo "✓ Notarized and stapled (profile: $NOTARY_PROFILE)"
fi
if [ "${SKIP_PKG:-0}" != "1" ]; then
    if [ -n "$INSTALLER_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
        echo "✓ Installer built, signed, notarized and stapled (${APP_NAME}.pkg)"
    elif [ -n "$INSTALLER_ID" ]; then
        echo "✓ Installer built and signed (${APP_NAME}.pkg) — not notarized"
    else
        echo "✓ Installer built (${APP_NAME}.pkg) — unsigned, local testing only"
    fi
fi
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo ""
    echo "=== For Universal Binary Distribution ==="
    echo "Binary supports both Intel (x86_64) and Apple Silicon (arm64)"
fi
echo ""
if [ -n "$DEVELOPER_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo "=== Ready for Distribution ==="
    echo "App bundle is signed, notarized, and stapled — ready to distribute directly."
else
    echo "=== Remaining Steps for Distribution ==="
    if [ -z "$DEVELOPER_ID" ]; then
        echo "1. Get an Apple Developer ID certificate, then re-run with: DEVELOPER_ID=\"Developer ID Application: Your Name\" ./build_production.sh"
    fi
    if [ -z "$NOTARY_PROFILE" ]; then
        echo "2. Store notarization credentials once: xcrun notarytool store-credentials \"<profile-name>\" --apple-id <id> --team-id <team> --password <app-specific-password>"
        echo "3. Re-run with both set to notarize+staple automatically: DEVELOPER_ID=\"...\" NOTARY_PROFILE=\"<profile-name>\" ./build_production.sh"
    fi
    if [ "${SKIP_PKG:-0}" != "1" ] && [ -z "$INSTALLER_ID" ]; then
        echo "4. To ship the installer, sign it with a Developer ID *Installer* certificate (distinct from the Application one): INSTALLER_ID=\"Developer ID Installer: Your Name\" ./build_production.sh"
    fi
fi
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo ""
    echo "=== Universal Binary Installation ==="
    echo "This binary runs on both Intel and Apple Silicon Macs"
fi

echo ""
echo "=== To Install Locally ==="
echo "cp -R \"MacMuster.app\" /Applications/"
if [ "${SKIP_PKG:-0}" != "1" ]; then
    echo "  ...or via the installer: sudo installer -pkg \"${APP_NAME}.pkg\" -target /"
fi
echo ""
echo "Build artifacts in: ${APP_NAME}.app"

# Build summary
if [ "${BUILD_UNIVERSAL:-0}" = "1" ]; then
    echo ""
    echo "=== Universal Binary Build Summary ==="
    echo "To build universal binaries in the future:"
    echo "  BUILD_UNIVERSAL=1 ./build_production.sh"
fi
