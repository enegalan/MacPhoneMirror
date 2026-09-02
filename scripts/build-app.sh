#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="MacPhoneMirror"
BUILD_DIR="$PROJECT_ROOT/.build/release"
APP_BUNDLE="$PROJECT_ROOT/dist/$APP_NAME.app"

echo "==> Building $APP_NAME (release)..."
cd "$PROJECT_ROOT"
swift build -c release 2>&1

BINARY="$BUILD_DIR/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating .app bundle..."
rm -rf "$PROJECT_ROOT/dist"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist (rewrite version if VERSION env var is set)
PLIST_SRC="$PROJECT_ROOT/Sources/MacPhoneMirror/Info.plist"
PLIST_DST="$APP_BUNDLE/Contents/Info.plist"
cp "$PLIST_SRC" "$PLIST_DST"

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_DST"
    # Use major.minor.patch as the build number
    BUILD_NUM=$(echo "$VERSION" | tr -d '.')
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$PLIST_DST"
    echo "    Version set to $VERSION (build $BUILD_NUM)"
fi

# Copy processed resources (SPM places them in a .bundle directory)
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    echo "    Copied SPM resource bundle"
fi

# Copy Assets.xcassets directly if it exists as a raw directory
ASSETS_SRC="$PROJECT_ROOT/Sources/MacPhoneMirror/Assets.xcassets"
if [[ -d "$ASSETS_SRC" ]]; then
    cp -R "$ASSETS_SRC" "$APP_BUNDLE/Contents/Resources/"
    echo "    Copied Assets.xcassets"
fi

# Copy any additional resources
EXTRA_RESOURCES="$PROJECT_ROOT/Sources/MacPhoneMirror/Resources"
if [[ -d "$EXTRA_RESOURCES" ]]; then
    for item in "$EXTRA_RESOURCES"/*; do
        cp -R "$item" "$APP_BUNDLE/Contents/Resources/"
    done
    echo "    Copied additional resources"
fi

echo "==> App bundle created at: $APP_BUNDLE"
ls -la "$APP_BUNDLE"
