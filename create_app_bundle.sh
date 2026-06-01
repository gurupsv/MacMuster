#!/bin/bash

APP_DIR="MacMuster.app"
BIN_DIR=$(swift build --show-bin-path)
mkdir -p "$APP_DIR/Contents/MacOS"
rm -rf "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/MacMuster" "$APP_DIR/Contents/MacOS/"

cp Resources/MacMusterIconDark.icns "$APP_DIR/Contents/Resources/MacAppIcon.icns"
cp Resources/MacMusterIconLight.icns "$APP_DIR/Contents/Resources/"
cp Resources/MacMusterIconDark.icns "$APP_DIR/Contents/Resources/"
cp Resources/MacMusterIconLight.png "$APP_DIR/Contents/Resources/"
cp Resources/MacMusterIconDark.png "$APP_DIR/Contents/Resources/"
cp Resources/MacMusterMenuBarTemplate.png "$APP_DIR/Contents/Resources/"
echo "MacMuster icons added"

cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
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
    <string>13.0</string>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_DIR"

echo "App bundle created: $APP_DIR"
ls -la "$APP_DIR/Contents/MacOS/"
ls -la "$APP_DIR/Contents/Resources/"
