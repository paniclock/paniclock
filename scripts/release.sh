#!/bin/bash
set -e

VERSION="1.0.0"
APP_NAME="PanicLock"
SCHEME="PanicLock"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

cd "$PROJECT_DIR"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build archive
xcodebuild -project PanicLock.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    archive

# Check if Developer ID certificate is available
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "=== Exporting with Developer ID signing ==="
    
    xcodebuild -exportArchive \
        -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
        -exportPath "$BUILD_DIR" \
        -exportOptionsPlist ExportOptions.plist

    echo "=== Zipping app for notarization ==="
    ditto -c -k --keepParent "$BUILD_DIR/${APP_NAME}.app" "$BUILD_DIR/${APP_NAME}.zip"

    echo "=== Notarizing App ==="
    xcrun notarytool submit "$BUILD_DIR/${APP_NAME}.zip" \
        --keychain-profile "notarytool-profile" \
        --wait

    echo "=== Stapling ==="
    xcrun stapler staple "$BUILD_DIR/${APP_NAME}.app"
    
    # Clean up zip
    rm "$BUILD_DIR/${APP_NAME}.zip"
    
    NOTARIZE_DMG=true
else
    echo "=== No Developer ID certificate found ==="
    echo "Extracting app from archive with development signature..."
    
    cp -R "$BUILD_DIR/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app" "$BUILD_DIR/"
    
    echo ""
    echo "WARNING: App is signed with development certificate only."
    echo "Users will need to right-click > Open to bypass Gatekeeper."
    echo ""
    
    NOTARIZE_DMG=false
fi

echo "=== Creating DMG ==="
mkdir -p "$BUILD_DIR/dmg"
cp -R "$BUILD_DIR/${APP_NAME}.app" "$BUILD_DIR/dmg/"
ln -s /Applications "$BUILD_DIR/dmg/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$BUILD_DIR/dmg" \
    -ov -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

# Clean up temp folder
rm -rf "$BUILD_DIR/dmg"

# Notarize the DMG if Developer ID is available
if [ "$NOTARIZE_DMG" = true ]; then
    echo "=== Notarizing DMG ==="
    xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
        --keychain-profile "notarytool-profile" \
        --wait

    xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
fi

echo ""
echo "=== Done! ==="
echo "DMG: $BUILD_DIR/$DMG_NAME"
echo ""
echo "To create a GitHub release:"
echo "  git tag v${VERSION}"
echo "  git push origin v${VERSION}"
echo "  gh release create v${VERSION} '$BUILD_DIR/$DMG_NAME' --title 'v${VERSION}' --notes-file CHANGELOG.md"
