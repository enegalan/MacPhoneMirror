#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="MacPhoneMirror"
APP_BUNDLE="$PROJECT_ROOT/dist/$APP_NAME.app"
DMG_NAME="${APP_NAME}-${VERSION:-latest}.dmg"
DMG_PATH="$PROJECT_ROOT/dist/$DMG_NAME"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Error: $APP_BUNDLE not found. Run 'make bundle' first."
    exit 1
fi

echo "==> Creating DMG..."
mkdir -p "$PROJECT_ROOT/dist"

# Create a temporary directory for the DMG contents
DMG_STAGING="$PROJECT_ROOT/dist/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app bundle
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create Applications symlink
ln -s /Applications "$DMG_STAGING/Applications"

# Remove old DMG if it exists
rm -f "$DMG_PATH"

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Cleanup
rm -rf "$DMG_STAGING"

echo "==> DMG created at: $DMG_PATH"
ls -lh "$DMG_PATH"
