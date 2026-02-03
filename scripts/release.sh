#!/bin/bash
set -e

VERSION="1.0.0"
APP_NAME="PanicLock"
SCHEME="PanicLock"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
STATE_FILE="$BUILD_DIR/.release-state"

cd "$PROJECT_DIR"

# Parse command line arguments
ACTION="build"  # default action
while [[ $# -gt 0 ]]; do
    case $1 in
        --status)
            ACTION="status"
            shift
            ;;
        --resume)
            ACTION="resume"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (no args)   Build, sign, notarize, and create DMG"
            echo "  --status    Check notarization status of pending submission"
            echo "  --resume    Resume after notarization completes (staple + create DMG)"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to save state
save_state() {
    echo "SUBMISSION_ID=$1" > "$STATE_FILE"
    echo "APP_HASH=$2" >> "$STATE_FILE"
    echo "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE_FILE"
}

# Function to load state
load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        return 0
    else
        return 1
    fi
}

# Handle --status
if [ "$ACTION" = "status" ]; then
    if ! load_state; then
        echo "No pending release found. Run without arguments to start a new build."
        exit 1
    fi
    echo "=== Checking notarization status ==="
    echo "Submission ID: $SUBMISSION_ID"
    echo "Build date: $BUILD_DATE"
    echo ""
    xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "notarytool-profile"
    exit 0
fi

# Handle --resume
if [ "$ACTION" = "resume" ]; then
    if ! load_state; then
        echo "No pending release found. Run without arguments to start a new build."
        exit 1
    fi
    
    echo "=== Resuming release ==="
    echo "Submission ID: $SUBMISSION_ID"
    
    # Check if notarization is complete
    STATUS=$(xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "notarytool-profile" 2>&1 | grep "status:" | head -1 | awk '{print $2}')
    
    if [ "$STATUS" = "In" ]; then
        echo ""
        echo "Notarization still in progress. Check back later with: $0 --status"
        exit 1
    elif [ "$STATUS" != "Accepted" ]; then
        echo ""
        echo "Notarization failed with status: $STATUS"
        echo "Check logs with: xcrun notarytool log $SUBMISSION_ID --keychain-profile notarytool-profile"
        exit 1
    fi
    
    echo "Notarization accepted!"
    
    # Verify the app still exists
    if [ ! -d "$BUILD_DIR/${APP_NAME}.app" ]; then
        echo "ERROR: App not found at $BUILD_DIR/${APP_NAME}.app"
        echo "The build artifacts may have been deleted. Run without arguments to rebuild."
        exit 1
    fi
    
    echo "=== Stapling ==="
    xcrun stapler staple "$BUILD_DIR/${APP_NAME}.app"
    
    # Clean up the zip now that we've stapled
    rm -f "$BUILD_DIR/${APP_NAME}.zip"
    
    # Continue to DMG creation
    NOTARIZE_DMG=true
    
    # Jump to DMG creation (uses the existing app)
    echo "=== Creating DMG ==="
    rm -rf "$BUILD_DIR/dmg"
    mkdir -p "$BUILD_DIR/dmg"
    cp -R "$BUILD_DIR/${APP_NAME}.app" "$BUILD_DIR/dmg/"
    ln -s /Applications "$BUILD_DIR/dmg/Applications"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$BUILD_DIR/dmg" \
        -ov -format UDZO \
        "$BUILD_DIR/$DMG_NAME"

    rm -rf "$BUILD_DIR/dmg"

    if [ "$NOTARIZE_DMG" = true ]; then
        echo "=== Notarizing DMG ==="
        xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
            --keychain-profile "notarytool-profile" \
            --wait

        xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
    fi
    
    # Clean up state file on success
    rm -f "$STATE_FILE"

    echo ""
    echo "=== Done! ==="
    echo "DMG: $BUILD_DIR/$DMG_NAME"
    echo ""
    echo "To create a GitHub release:"
    echo "  git tag v${VERSION}"
    echo "  git push origin v${VERSION}"
    echo "  gh release create v${VERSION} '$BUILD_DIR/$DMG_NAME' --title 'v${VERSION}' --notes-file CHANGELOG.md"
    exit 0
fi

# === Full build flow ===

# Check for existing pending notarization
if load_state 2>/dev/null; then
    echo "WARNING: A previous build is pending notarization."
    echo "  Submission ID: $SUBMISSION_ID"
    echo "  Build date: $BUILD_DATE"
    echo ""
    echo "Options:"
    echo "  1. Run '$0 --status' to check notarization status"
    echo "  2. Run '$0 --resume' to continue after notarization completes"
    echo "  3. Delete $STATE_FILE and run again to start fresh (loses pending notarization)"
    echo ""
    read -p "Start a new build anyway? This will abandon the pending notarization. [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

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

    # Get the cdhash for tracking
    APP_HASH=$(codesign -dvvv "$BUILD_DIR/${APP_NAME}.app" 2>&1 | grep "CDHash=" | head -1 | cut -d= -f2)

    echo "=== Submitting for Notarization ==="
    echo "This may take several minutes to hours. You can:"
    echo "  - Wait here for completion"
    echo "  - Press Ctrl+C and run '$0 --status' later to check"
    echo "  - Run '$0 --resume' after notarization completes"
    echo ""
    
    # Submit and capture the submission ID
    SUBMIT_OUTPUT=$(xcrun notarytool submit "$BUILD_DIR/${APP_NAME}.zip" \
        --keychain-profile "notarytool-profile" 2>&1 | tee /dev/tty)
    
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    
    if [ -z "$SUBMISSION_ID" ]; then
        echo "ERROR: Failed to get submission ID"
        exit 1
    fi
    
    # Save state immediately after submission
    save_state "$SUBMISSION_ID" "$APP_HASH"
    echo ""
    echo "Saved release state. Submission ID: $SUBMISSION_ID"
    
    # Now wait for completion
    echo "=== Waiting for Notarization ==="
    xcrun notarytool wait "$SUBMISSION_ID" --keychain-profile "notarytool-profile"
    
    # Check result
    STATUS=$(xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "notarytool-profile" 2>&1 | grep "status:" | head -1 | awk '{print $2}')
    
    if [ "$STATUS" != "Accepted" ]; then
        echo ""
        echo "Notarization failed with status: $STATUS"
        echo "Check logs with: xcrun notarytool log $SUBMISSION_ID --keychain-profile notarytool-profile"
        echo ""
        echo "State saved. After fixing issues, rebuild with: $0"
        exit 1
    fi

    echo "=== Stapling ==="
    xcrun stapler staple "$BUILD_DIR/${APP_NAME}.app"
    
    # Clean up zip after successful staple
    rm -f "$BUILD_DIR/${APP_NAME}.zip"
    
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

# Clean up state file on success
rm -f "$STATE_FILE"

echo ""
echo "=== Done! ==="
echo "DMG: $BUILD_DIR/$DMG_NAME"
echo ""
echo "To create a GitHub release:"
echo "  git tag v${VERSION}"
echo "  git push origin v${VERSION}"
echo "  gh release create v${VERSION} '$BUILD_DIR/$DMG_NAME' --title 'v${VERSION}' --notes-file CHANGELOG.md"
