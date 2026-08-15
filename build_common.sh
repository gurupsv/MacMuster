#!/bin/bash
# Shared build configuration, sourced by create_app_bundle.sh and build_production.sh.
# Not executable on its own.

# Files copied into Contents/Resources.
#
# This list is deliberately explicit. It replaced `cp -R Resources/*`, which shipped everything
# in the directory whether the app used it or not — including MacMusterIconDark.pxd, the
# editable Pixelmator source for the icon, and ~2.8 MB of image files nothing references.
#
# Anything added to Resources/ for authoring purposes stays out of the bundle unless it is
# listed here on purpose.
BUNDLE_RESOURCES=(
    "MacMusterIconDark.icns"        # CFBundleIconFile — the static bundle icon Finder reads
    "MacMusterIconDark.png"         # runtime Dock icon, dark appearance (AppDelegate)
    "MacMusterIconLight.png"        # runtime Dock icon, light appearance (AppDelegate)
    "MacMusterMenuBarTemplate.png"  # status-bar item image (StatusBarManager)
    "PrivacyInfo.xcprivacy"         # privacy manifest — read by Apple's tooling, not by code
)

# Copies the listed resources into $1 (a Contents/Resources directory).
#
# Fails loudly on a missing file. The wildcard copy this replaced would happily produce a
# bundle with no menu-bar icon and say nothing about it.
copy_bundle_resources() {
    local dest="$1"
    local src="Resources"
    local missing=0

    for res in "${BUNDLE_RESOURCES[@]}"; do
        if [ -f "${src}/${res}" ]; then
            cp "${src}/${res}" "${dest}/"
        else
            echo "Error: required resource not found: ${src}/${res}" >&2
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        return 1
    fi

    echo "Copied ${#BUNDLE_RESOURCES[@]} resources into the bundle."
}

# Asset catalog compiled into Contents/Resources/Assets.car.
ASSET_CATALOG="MacMuster.xcassets"

# Compiles $ASSET_CATALOG with actool into $1 (a Contents/Resources directory).
#
# SwiftPM does not compile asset catalogs, so without this step the .xcassets is simply absent
# from the bundle and every NSImage(named:) lookup against it returns nil at runtime. actool
# ships with Xcode, so this is skipped with a warning when only the Command Line Tools are
# installed rather than failing the build.
#
# --app-icon is deliberately not passed: the catalog currently holds an .imageset, which is a
# runtime-loadable image, not an app icon. See notes in the README/PR description.
compile_asset_catalog() {
    local dest="$1"

    if [ ! -d "$ASSET_CATALOG" ]; then
        echo "No ${ASSET_CATALOG} found — skipping asset catalog compilation."
        return 0
    fi

    if ! xcrun --find actool >/dev/null 2>&1; then
        echo "Warning: actool not found (needs full Xcode, not just Command Line Tools)." >&2
        echo "         ${ASSET_CATALOG} will NOT be in the bundle; catalog images will fail to load." >&2
        return 0
    fi

    # Explicit XXXXXX template: BSD mktemp rejects a bare -t prefix.
    local partial
    partial="$(mktemp "${TMPDIR:-/tmp}/macmuster_actool.XXXXXX")"

    # actool reports failures in a plist on stdout rather than via exit status, so the presence
    # of Assets.car afterwards is the real success check.
    xcrun actool "$ASSET_CATALOG" \
        --compile "$dest" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --output-partial-info-plist "$partial" \
        >/dev/null 2>&1
    rm -f "$partial"

    if [ ! -f "${dest}/Assets.car" ]; then
        echo "Error: actool did not produce Assets.car from ${ASSET_CATALOG}" >&2
        return 1
    fi

    echo "Compiled ${ASSET_CATALOG} -> Assets.car ($(du -h "${dest}/Assets.car" | cut -f1))"
}
