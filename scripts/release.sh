#!/bin/bash
set -e

APP_NAME="PanicLock"
SCHEME="PanicLock"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYCHAIN_PROFILE="notarytool-profile"

cd "$PROJECT_DIR"

# Extract version from Xcode project
VERSION=$(xcodebuild -project PanicLock.xcodeproj -scheme "$SCHEME" -showBuildSettings 2>/dev/null | grep "MARKETING_VERSION" | head -1 | awk '{print $3}')
if [ -z "$VERSION" ]; then
    echo "ERROR: Could not extract version from Xcode project"
    exit 1
fi

# Version-specific build directory (allows parallel notarizations)
BUILD_DIR="$PROJECT_DIR/build/release/$VERSION"
STATE_FILE="$BUILD_DIR/.release-state"
DMG_NAME="${APP_NAME}.dmg"

# Show help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0"
    echo ""
    echo "Builds, signs, notarizes, and creates a DMG for release."
    echo ""
    echo "The script automatically detects the current phase and"
    echo "continues from where it left off:"
    echo ""
    echo "  Phase 1: Build app and submit for notarization"
    echo "  Phase 2: Check app notarization -> staple -> create DMG -> submit DMG"
    echo "  Phase 3: Check DMG notarization -> staple -> done"
    echo ""
    echo "Each notarization step exits after submission. Run again to continue."
    exit 0
fi

# =============================================================================
# State Management
# =============================================================================

save_state() {
    mkdir -p "$BUILD_DIR"
    # Use existing BUILD_DATE if available, otherwise create new one
    local build_date="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local git_commit="${GIT_COMMIT:-$(git rev-parse HEAD)}"
    cat > "$STATE_FILE" << EOF
PHASE=$1
APP_SUBMISSION_ID=$2
APP_CDHASH=$3
DMG_SUBMISSION_ID=$4
DMG_CDHASH=$5
BUILD_DATE=$build_date
GIT_COMMIT=$git_commit
EOF
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        return 0
    else
        return 1
    fi
}

get_app_cdhash() {
    if [ -d "$BUILD_DIR/${APP_NAME}.app" ]; then
        codesign -dvvv "$BUILD_DIR/${APP_NAME}.app" 2>&1 | grep "CDHash=" | head -1 | cut -d= -f2
    fi
}

get_dmg_cdhash() {
    if [ -f "$BUILD_DIR/$DMG_NAME" ]; then
        # For DMGs, we use a SHA-256 hash since they're not code-signed
        shasum -a 256 "$BUILD_DIR/$DMG_NAME" | cut -d' ' -f1
    fi
}

check_notarization_status() {
    local submission_id="$1"
    xcrun notarytool info "$submission_id" --keychain-profile "$KEYCHAIN_PROFILE" 2>&1 | grep "status:" | head -1 | awk '{print $2}'
}

submit_for_notarization() {
    local file="$1"
    local output=$(xcrun notarytool submit "$file" --keychain-profile "$KEYCHAIN_PROFILE" 2>&1 | tee /dev/tty)
    echo "$output" | grep "id:" | head -1 | awk '{print $2}'
}

create_dmg() {
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
    
    echo "=== Signing DMG ==="
    codesign --force --sign "Developer ID Application" "$BUILD_DIR/$DMG_NAME"
    echo "DMG signed."
}

# =============================================================================
# Phase Handlers
# =============================================================================

handle_app_notarization_pending() {
    echo "=== Phase 2: App Notarization Pending ==="
    echo ""
    echo "  Submission ID: $APP_SUBMISSION_ID"
    echo "  App CDHash: $APP_CDHASH"
    echo "  Submitted: $BUILD_DATE"
    echo ""
    
    # Verify local app still matches
    local current_cdhash=$(get_app_cdhash)
    if [ "$current_cdhash" != "$APP_CDHASH" ]; then
        echo "ERROR: Local app has changed since submission!"
        echo "  Expected: $APP_CDHASH"
        echo "  Found: $current_cdhash"
        echo ""
        echo "Delete $STATE_FILE and run again to start fresh."
        exit 1
    fi
    
    echo "Checking notarization status..."
    local status=$(check_notarization_status "$APP_SUBMISSION_ID")
    
    if [ "$status" = "Accepted" ]; then
        echo "App notarization ACCEPTED!"
        echo ""
        
        echo "=== Stapling App ==="
        xcrun stapler staple "$BUILD_DIR/${APP_NAME}.app"
        
        # Verify stapling succeeded
        if ! codesign -dvvv "$BUILD_DIR/${APP_NAME}.app" 2>&1 | grep -q "Notarization Ticket=stapled"; then
            echo "ERROR: App stapling failed! The app inside the DMG would not work offline."
            echo "Try running: xcrun stapler staple '$BUILD_DIR/${APP_NAME}.app'"
            exit 1
        fi
        echo "App stapling verified."
        
        # Clean up app zip
        rm -f "$BUILD_DIR/${APP_NAME}.zip"
        
        # Clean up archive (no longer needed)
        rm -rf "$BUILD_DIR/${APP_NAME}.xcarchive"
        
        echo ""
        create_dmg
        
        echo ""
        echo "=== Submitting DMG for Notarization ==="
        local dmg_cdhash=$(get_dmg_cdhash)
        echo "DMG SHA-256: $dmg_cdhash"
        
        local dmg_submission_id=$(submit_for_notarization "$BUILD_DIR/$DMG_NAME")
        
        if [ -z "$dmg_submission_id" ]; then
            echo "ERROR: Failed to get DMG submission ID"
            exit 1
        fi
        
        save_state "dmg_submitted" "$APP_SUBMISSION_ID" "$APP_CDHASH" "$dmg_submission_id" "$dmg_cdhash"
        
        echo ""
        echo "=============================================="
        echo "  DMG notarization submitted!"
        echo "=============================================="
        echo ""
        echo "  Submission ID: $dmg_submission_id"
        echo ""
        echo "  Run this script again to check status."
        echo "=============================================="
        exit 0
        
    elif [ "$status" = "In" ]; then
        echo "App notarization still In Progress"
        echo ""
        echo "Apple is still processing. This can take minutes to hours."
        echo "Run this script again later to check status."
        echo ""
        xcrun notarytool info "$APP_SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
        exit 0
        
    elif [ "$status" = "Invalid" ]; then
        echo "App notarization REJECTED"
        echo ""
        xcrun notarytool log "$APP_SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
        echo ""
        echo "Fix the issues, delete $STATE_FILE, and run again."
        exit 1
        
    else
        echo "Unexpected status: $status"
        xcrun notarytool info "$APP_SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
        exit 1
    fi
}

handle_dmg_notarization_pending() {
    echo "=== Phase 3: DMG Notarization Pending ==="
    echo ""
    echo "  Submission ID: $DMG_SUBMISSION_ID"
    echo "  DMG SHA-256: $DMG_CDHASH"
    echo "  Submitted: $BUILD_DATE"
    echo ""
    
    # Verify DMG exists
    if [ ! -f "$BUILD_DIR/$DMG_NAME" ]; then
        echo "ERROR: DMG not found at $BUILD_DIR/$DMG_NAME"
        echo "Delete $STATE_FILE and run again to start fresh."
        exit 1
    fi
    
    # Verify DMG hasn't changed
    local current_dmg_hash=$(get_dmg_cdhash)
    if [ -n "$DMG_CDHASH" ] && [ "$current_dmg_hash" != "$DMG_CDHASH" ]; then
        echo "ERROR: DMG has changed since submission!"
        echo "  Expected: $DMG_CDHASH"
        echo "  Found: $current_dmg_hash"
        echo ""
        echo "Delete $STATE_FILE and run again to start fresh."
        exit 1
    fi
    
    echo "Checking notarization status..."
    local status=$(check_notarization_status "$DMG_SUBMISSION_ID")
    
    if [ "$status" = "Accepted" ]; then
        echo "DMG notarization ACCEPTED!"
        echo ""
        
        echo "=== Stapling DMG ==="
        xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
        
        # Clean up state file
        rm -f "$STATE_FILE"
        
        echo ""
        echo "=============================================="
        echo "  Release Complete!"
        echo "=============================================="
        echo ""
        echo "  DMG: $BUILD_DIR/$DMG_NAME"
        echo ""
        echo "  To publish on GitHub:"
        if git tag -l "v${VERSION}" | grep -q "v${VERSION}"; then
            echo "    (Tag v${VERSION} already exists)"
        else
            echo "    git tag v${VERSION}"
            echo "    git push origin v${VERSION}"
        fi
        echo "    gh release create v${VERSION} '$BUILD_DIR/$DMG_NAME' \\"
        echo "      --title 'v${VERSION}' --notes-file CHANGELOG.md"
        echo ""
        exit 0
        
    elif [ "$status" = "In" ]; then
        echo "DMG notarization still In Progress"
        echo ""
        echo "Apple is still processing. This can take minutes to hours."
        echo "Run this script again later to check status."
        echo ""
        xcrun notarytool info "$DMG_SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
        exit 0
        
    elif [ "$status" = "Invalid" ]; then
        echo "DMG notarization REJECTED"
        echo ""
        xcrun notarytool log "$DMG_SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
        echo ""
        echo "This is unusual for a DMG containing a notarized app."
        echo "Check the logs above for details."
        exit 1
        
    else
        echo "Unexpected status: $status"
        xcrun notarytool info "$DMG_SUBMISSION_ID" --keychain-profile "$KEYCHAIN_PROFILE"
        exit 1
    fi
}

do_fresh_build() {
    echo "=== Phase 1: Building ${APP_NAME} v${VERSION} ==="
    echo ""
    
    # Check if git tag already exists before building
    if git tag -l "v${VERSION}" | grep -q "v${VERSION}"; then
        echo "WARNING: Git tag v${VERSION} already exists!"
        echo "If re-releasing, delete it first:"
        echo "  git tag -d v${VERSION} && git push origin :refs/tags/v${VERSION}"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
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
    if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        echo ""
        echo "=== No Developer ID certificate found ==="
        echo "Cannot create a distributable release without Developer ID signing."
        echo ""
        echo "To sign with development certificate only (for testing):"
        echo "  xcodebuild -exportArchive ... (manual steps)"
        exit 1
    fi
    
    echo "=== Exporting with Developer ID signing ==="
    
    xcodebuild -exportArchive \
        -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
        -exportPath "$BUILD_DIR" \
        -exportOptionsPlist ExportOptions.plist

    echo "=== Zipping app for notarization ==="
    ditto -c -k --keepParent "$BUILD_DIR/${APP_NAME}.app" "$BUILD_DIR/${APP_NAME}.zip"

    local app_cdhash=$(get_app_cdhash)
    echo "App CDHash: $app_cdhash"

    echo ""
    echo "=== Submitting App for Notarization ==="
    
    local submission_id=$(submit_for_notarization "$BUILD_DIR/${APP_NAME}.zip")
    
    if [ -z "$submission_id" ]; then
        echo "ERROR: Failed to get submission ID"
        exit 1
    fi
    
    save_state "app_submitted" "$submission_id" "$app_cdhash" "" ""
    
    echo ""
    echo "=============================================="
    echo "  App notarization submitted!"
    echo "=============================================="
    echo ""
    echo "  Submission ID: $submission_id"
    echo "  CDHash: $app_cdhash"
    echo ""
    echo "  Apple typically takes a few minutes to several"
    echo "  hours to process notarization requests."
    echo ""
    echo "  Run this script again to check status."
    echo "=============================================="
}

# =============================================================================
# Main Logic
# =============================================================================

echo "=== PanicLock Release Script ==="
echo ""

# Check for existing state
if load_state 2>/dev/null; then
    echo "Found existing release in progress..."
    echo "  Phase: $PHASE"
    echo "  Build started: $BUILD_DATE"
    echo ""
    
    case "$PHASE" in
        app_submitted)
            handle_app_notarization_pending
            ;;
        dmg_submitted)
            handle_dmg_notarization_pending
            ;;
        *)
            echo "Unknown phase: $PHASE"
            echo "Delete $STATE_FILE and run again to start fresh."
            exit 1
            ;;
    esac
    # Phase handlers always exit, so we should never reach here
    exit 0
fi

# Check if we have an existing app that might already be notarized
if [ -d "$BUILD_DIR/${APP_NAME}.app" ]; then
    echo "Found existing app: $BUILD_DIR/${APP_NAME}.app"
    local_cdhash=$(get_app_cdhash)
    echo "  CDHash: $local_cdhash"
    echo ""
    
    # Try to staple it (will succeed if already notarized)
    echo "Checking if app is already notarized..."
    if xcrun stapler staple "$BUILD_DIR/${APP_NAME}.app" >/dev/null 2>&1; then
        echo "App is already notarized and stapled!"
        echo ""
        
        # Check for existing DMG
        if [ -f "$BUILD_DIR/$DMG_NAME" ]; then
            echo "Checking if DMG is already notarized..."
            if xcrun stapler validate "$BUILD_DIR/$DMG_NAME" >/dev/null 2>&1; then
                echo "DMG is already notarized!"
                echo ""
                echo "=============================================="
                echo "  Release already complete!"
                echo "=============================================="
                echo "  DMG: $BUILD_DIR/$DMG_NAME"
                exit 0
            else
                echo "DMG exists but is not notarized."
                read -p "Submit DMG for notarization? [Y/n] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Nn]$ ]]; then
                    exit 1
                fi
                
                echo ""
                echo "=== Submitting DMG for Notarization ==="
                dmg_submission_id=$(submit_for_notarization "$BUILD_DIR/$DMG_NAME")
                
                if [ -z "$dmg_submission_id" ]; then
                    echo "ERROR: Failed to get DMG submission ID"
                    exit 1
                fi
                
                dmg_hash=$(get_dmg_cdhash)
                save_state "dmg_submitted" "" "$local_cdhash" "$dmg_submission_id" "$dmg_hash"
                
                echo ""
                echo "=============================================="
                echo "  DMG notarization submitted!"
                echo "=============================================="
                echo "  Submission ID: $dmg_submission_id"
                echo ""
                echo "  Run this script again to check status."
                echo "=============================================="
                exit 0
            fi
        else
            echo "No DMG found. Creating DMG..."
            echo ""
            
            create_dmg
            
            echo ""
            echo "=== Submitting DMG for Notarization ==="
            dmg_submission_id=$(submit_for_notarization "$BUILD_DIR/$DMG_NAME")
            
            if [ -z "$dmg_submission_id" ]; then
                echo "ERROR: Failed to get DMG submission ID"
                exit 1
            fi
            
            dmg_hash=$(get_dmg_cdhash)
            save_state "dmg_submitted" "" "$local_cdhash" "$dmg_submission_id" "$dmg_hash"
            
            echo ""
            echo "=============================================="
            echo "  DMG notarization submitted!"
            echo "=============================================="
            echo "  Submission ID: $dmg_submission_id"
            echo ""
            echo "  Run this script again to check status."
            echo "=============================================="
            exit 0
        fi
    else
        echo "App is not notarized."
        echo ""
        read -p "Start fresh build? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            exit 1
        fi
    fi
fi

# No state, no existing notarized app - do fresh build
do_fresh_build
