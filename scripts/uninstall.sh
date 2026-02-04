#!/bin/bash
#
# PanicLock Uninstall Script
# Completely removes PanicLock and all associated files
#

set -e

APP_NAME="PanicLock"
BUNDLE_ID="com.paniclock.app"
HELPER_ID="com.paniclock.helper"

echo "=== PanicLock Uninstall Script ==="
echo ""

# Check if running as root (we'll need sudo for some operations)
if [[ $EUID -eq 0 ]]; then
    echo "Please run without sudo. The script will prompt for password when needed."
    exit 1
fi

# Confirm uninstall
read -p "This will completely remove PanicLock. Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "=== Stopping processes ==="

# Kill the app
if pgrep -f "${APP_NAME}.app" > /dev/null 2>&1; then
    echo "Killing ${APP_NAME} app..."
    pkill -9 -f "${APP_NAME}.app" 2>/dev/null || true
    sleep 1
else
    echo "App not running."
fi

# Stop and remove the privileged helper
if [ -f "/Library/LaunchDaemons/${HELPER_ID}.plist" ] || [ -f "/Library/PrivilegedHelperTools/${HELPER_ID}" ]; then
    echo "Stopping privileged helper (requires admin password)..."
    sudo launchctl bootout "system/${HELPER_ID}" 2>/dev/null || true
    
    # Kill helper process if still running
    if pgrep -f "${HELPER_ID}" > /dev/null 2>&1; then
        sudo pkill -9 -f "${HELPER_ID}" 2>/dev/null || true
    fi
    
    echo "Removing helper files..."
    sudo rm -f "/Library/PrivilegedHelperTools/${HELPER_ID}"
    sudo rm -f "/Library/LaunchDaemons/${HELPER_ID}.plist"
else
    echo "Helper not installed."
fi

echo ""
echo "=== Removing application ==="

# Remove from /Applications
if [ -d "/Applications/${APP_NAME}.app" ]; then
    echo "Removing /Applications/${APP_NAME}.app..."
    rm -rf "/Applications/${APP_NAME}.app"
else
    echo "App not in /Applications."
fi

# Also check user Applications folder
if [ -d "$HOME/Applications/${APP_NAME}.app" ]; then
    echo "Removing ~/Applications/${APP_NAME}.app..."
    rm -rf "$HOME/Applications/${APP_NAME}.app"
fi

echo ""
echo "=== Removing login item ==="

# Remove from login items
osascript -e "tell application \"System Events\" to delete login item \"${APP_NAME}\"" 2>/dev/null && echo "Removed from login items." || echo "Not in login items."

echo ""
echo "=== Removing preferences and caches ==="

# Remove preferences
if [ -f "$HOME/Library/Preferences/${BUNDLE_ID}.plist" ]; then
    echo "Removing preferences..."
    rm -f "$HOME/Library/Preferences/${BUNDLE_ID}.plist"
fi

# Remove from defaults
defaults delete "${BUNDLE_ID}" 2>/dev/null || true

# Remove caches
if [ -d "$HOME/Library/Caches/${BUNDLE_ID}" ]; then
    echo "Removing caches..."
    rm -rf "$HOME/Library/Caches/${BUNDLE_ID}"
fi

# Remove Application Support
if [ -d "$HOME/Library/Application Support/${BUNDLE_ID}" ]; then
    echo "Removing Application Support..."
    rm -rf "$HOME/Library/Application Support/${BUNDLE_ID}"
fi

# Remove saved state
if [ -d "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState" ]; then
    echo "Removing saved state..."
    rm -rf "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState"
fi

# Remove containers (sandboxed apps)
if [ -d "$HOME/Library/Containers/${BUNDLE_ID}" ]; then
    echo "Removing containers..."
    rm -rf "$HOME/Library/Containers/${BUNDLE_ID}"
fi

echo ""
echo "=== Verifying uninstall ==="

errors=0

# Check for running processes
if pgrep -f "${APP_NAME}" > /dev/null 2>&1; then
    echo "WARNING: ${APP_NAME} processes still running"
    ps aux | grep -i "${APP_NAME}" | grep -v grep
    errors=$((errors + 1))
else
    echo "✓ No processes running"
fi

# Check for helper
if [ -f "/Library/PrivilegedHelperTools/${HELPER_ID}" ]; then
    echo "WARNING: Helper still exists"
    errors=$((errors + 1))
else
    echo "✓ Helper removed"
fi

# Check for LaunchDaemon
if [ -f "/Library/LaunchDaemons/${HELPER_ID}.plist" ]; then
    echo "WARNING: LaunchDaemon still exists"
    errors=$((errors + 1))
else
    echo "✓ LaunchDaemon removed"
fi

# Check for app
if [ -d "/Applications/${APP_NAME}.app" ]; then
    echo "WARNING: App still in /Applications"
    errors=$((errors + 1))
else
    echo "✓ App removed"
fi

echo ""
if [ $errors -eq 0 ]; then
    echo "=============================================="
    echo "  PanicLock uninstalled successfully!"
    echo "=============================================="
else
    echo "=============================================="
    echo "  Uninstall completed with $errors warning(s)"
    echo "=============================================="
fi
