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

# Show help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0"
    echo ""
    echo "Builds, signs, notarizes, and creates a DMG for release."
    echo ""
    echo "The script automatically detects the current state and"
    echo "continues from where it left off:"
    echo ""
    echo "  1. No build exists      -> Builds and submits for notarization"
    echo "  2. Notarization pending -> Shows status (run again later)"
    echo "  3. Notarization accepted -> Staples and creates DMG"
    echo ""
    exit 0
fi

# Function to save state
save_state() {
    mkdir -p "$BUILD_DIR"
    cat > "$STATE_FILE" << EOF
SUBMISSION_ID=$1
APP_CDHASH=$2
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
GIT_COMMIT=$(git rev-parse HEAD)
EOF
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

# Function to get cdhash of local app
get_local_cdhash() {
    if [ -d "$BUILD_DIR/${APP_NAME}.app" ]; then
        codesign -dvvv "$BUILD_DIR/${APP_NAME}.app" 2>&1 | grep "CDHash=" | head -1 | cut -d= -f2
    fi
}

# Function to create DMG and finish release
finish_release() {
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

    echo "=== Notarizing DMG ==="
    xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
        --keychain-profile "notarytool-profile" \
        --wait

    xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
    
    rm -f "$STATE_FILE"
    rm -f "$BUILD_DIR/${APP_NAME}.zip"

    echo ""
    echo "=== Release Complete! ==="
    echo "DMG: $BUILD_DIR/$DMG_NAME"
    echo ""
    echo "To publish on GitHub:"
    echo "  git tag v${VERSION}"
    echo "  git push origin v${VERSION}"
    echo "  gh release create v${VERSION} '$BUILD_DIR/$DMG_NAME' --title 'v${VERSION}' --notes-file CHANGELOG.md"
}

# =============================================================================
# MAIN LOGIC - Detect state and take appropriate action
# =============================================================================

echo "=== PanicLock Release Script ==="
echo ""

# Check for local app
LOCAL_CDHASH=$(get_local_cdhash)
HAS_LOCAL_APP=false
if [ -n "$LOCAL_CDHASH" ]; then
    HAS_LOCAL_APP=true
fi

# Load saved state
HAS_STATE=false
if load_state 2>/dev/null; then
    HAS_STATE=true
fi

# If we have a local app and state, check notarization status
if [ "$HAS_LOCAL_APP" = true ] && [ "$HAS_STATE" = true ]; then
    echo "Found pending release:"
    echo "  App: $BUILD_DIR/${APP_NAME}.app"
    echo "  CDHash: $LOCAL_CDHASH"
    echo "  Submission: $SUBMISSION_ID"
    echo "  Submitted: $BUILD_DATE"
    echo ""
    
    # Verify the local app matches what we submitted
    if [ "$LOCAL_CDHASH" != "$APP_CDHASH" ]; then
        echo "WARNING: Local app CDHash doesn't match submitted build!"
        echo "  Expected: $APP_CDHASH"
        echo "  Found: $LOCAL_CDHASH"
        echo ""
        echo "The build artifacts may have been modified."
        read -p "Start a fresh build? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            exit 1
        fi
        # Fall through to fresh build below
        HAS_LOCAL_APP=false
        HAS_STATE=false
    else
        # Check notarization status
        echo "Checking notarization status..."
        STATUS=$(xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "notarytool-profile" 2>&1 | grep "status:" | head -1 | awk '{print $2}')
        
        if [ "$STATUS" = "Accepted" ]; then
            echo "Notarization ACCEPTED!"
            echo ""
            echo "=== Stapling ==="
            xcrun stapler staple "$BUILD_DIR/${APP_NAME}.app"
            
            finish_release
            exit 0
            
        elif [ "$STATUS" = "In" ]; then
            echo "Notarization still In Progress"
            echo ""
            echo "Apple is still processing. This can take minutes to hours."
            echo "Run this script again later to check status."
            echo ""
            xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "notarytool-profile"
            exit 0
            
        elif [ "$STATUS" = "Invalid" ]; then
            echo "Notarization REJECTED"
            echo ""
            echo "Fetching rejection details..."
            xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "notarytool-profile"
            echo ""
            echo "Fix the issues and run this script again to rebuild."
            rm -f "$STATE_FILE"
            exit 1
            
        else
            echo "Notarization status: $STATUS"
            echo ""
            xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "notarytool-profile"
            exit 1
        fi
    fi

# If we have a local app but no state, check if it's already notarized
elif [ "$HAS_LOCAL_APP" = true ]; then
    echo "Found app without submission state:"
    echo "  App: $BUILD_DIR/${APP_NAME}.app"
    echo "  CDHash: $LOCAL_CDHASH"
    echo ""
    echo "Checking if Apple has a notarization ticket..."
    
    if xcrun stapler staple "$BUILD_DIR/${APP_NAME}.app" 2>&1; then
        echo ""
        echo "App is already notarized!"
        
        # Check if DMG already exists
        if [ -f "$BUILD_DIR/$DMG_NAME" ]; then
            echo "DMG already exists: $BUILD_DIR/$DMG_NAME"
            echo ""
            read -p "Recreate DMG? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo ""
                echo "Release ready at: $BUILD_DIR/$DMG_NAME"
                exit 0
            fi
        fi
        
        finish_release
        exit 0
    else
        echo "No notarization ticket found."
        echo ""
        read -p "Submit this app for notarization? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            exit 1
        fi
        
        # Zip and submit
        echo "=== Zipping app for notarization ==="
        ditto -c -k --keepParent "$BUILD_DIR/${APP_NAME}.app" "$BUILD_DIR/${APP_NAME}.zip"
        
        echo "=== Submitting for Notarization ==="
        SUBMIT_OUTPUT=$(xcrun notarytool submit "$BUILD_DIR/${APP_NAME}.zip" \
            --keychain-profile "notarytool-profile" 2>&1 | tee /dev/tty)
        
        SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
        
        if [ -z "$SUBMISSION_ID" ]; then
            echo "ERROR: Failed to get submission ID"
            exit 1
        fi
        
        save_state "$SUBMISSION_ID" "$LOCAL_CDHASH"
        
        echo ""
        echo "=============================================="
        echo "  Notarization submitted!"
        echo "  Submission ID: $SUBMISSION_ID"
        echo ""
        echo "  Run this script again to check status."
        echo "=============================================="
        exit 0
    fi
fi

# =============================================================================
# No local app - do a fresh build
# =============================================================================

echo "No existing build found. Starting fresh build..."
echo ""

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "=== Building ${APP_NAME} v${VERSION} ==="

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

    APP_CDHASH=$(codesign -dvvv "$BUILD_DIR/${APP_NAME}.app" 2>&1 | grep "CDHash=" | head -1 | cut -d= -f2)
    echo "App CDHash: $APP_CDHASH"

    echo "=== Submitting for Notarization ==="
    
    SUBMIT_OUTPUT=$(xcrun notarytool submit "$BUILD_DIR/${APP_NAME}.zip" \
        --keychain-profile "notarytool-profile" 2>&1 | tee /dev/tty)
    
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    
    if [ -z "$SUBMISSION_ID" ]; then
        echo "ERROR: Failed to get submission ID"
        exit 1
    fi
    
    save_state "$SUBMISSION_ID" "$APP_CDHASH"
    
    echo ""
    echo "=============================================="
    echo "  Notarization submitted!"
    echo "=============================================="
    echo ""
    echo "  Submission ID: $SUBMISSION_ID"
    echo "  CDHash: $APP_CDHASH"
    echo ""
    echo "  Apple typically takes a few minutes to several"
    echo "  hours to process notarization requests."
    echo ""
    echo "  Run this script again to check status and"
    echo "  complete the release."
    echo "=============================================="
    
else
    echo "=== No Developer ID certificate found ==="
    echo "Extracting app from archive with development signature..."
    
    cp -R "$BUILD_DIR/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app" "$BUILD_DIR/"
    
    echo ""
    echo "WARNING: App is signed with development certificate only."
    echo "Users will need to right-click > Open to bypass Gatekeeper."
    echo ""
    
    echo "=== Creating DMG ==="
    mkdir -p "$BUILD_DIR/dmg"
    cp -R "$BUILD_DIR/${APP_NAME}.app" "$BUILD_DIR/dmg/"
    ln -s /Applications "$BUILD_DIR/dmg/Applications"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$BUILD_DIR/dmg" \
        -ov -format UDZO \
        "$BUILD_DIR/$DMG_NAME"

    rm -rf "$BUILD_DIR/dmg"

    echo ""
    echo "=== Done (unsigned) ==="
    echo "DMG: $BUILD_DIR/$DMG_NAME"
fi
