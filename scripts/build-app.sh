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

# Copy binary and strip local symbols
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
strip "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo "    Stripped binary: $(du -h "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | awk '{print $1}')"

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

# Ship only what the packaged app needs:
# - logo.png for menu bar / About (Bundle.main)
# - AppIcon.icns for Dock / Finder (CFBundleIconFile)
LOGO_SRC="$PROJECT_ROOT/Sources/MacPhoneMirror/Resources/logo.png"
if [[ -f "$LOGO_SRC" ]]; then
    cp "$LOGO_SRC" "$APP_BUNDLE/Contents/Resources/logo.png"
    echo "    Copied logo.png"
else
    echo "Error: logo.png not found at $LOGO_SRC" >&2
    exit 1
fi

# Build AppIcon.icns for Dock/Finder. Cap at 512px — the 1024 (@2x of 512)
# slot alone is ~500 KB and is not worth the bundle weight for this app.
ICON_SRC="$PROJECT_ROOT/Sources/MacPhoneMirror/Resources/app-icon.png"
if [[ ! -f "$ICON_SRC" ]]; then
    ICON_SRC="$PROJECT_ROOT/art/app-icon.png"
fi
if [[ -f "$ICON_SRC" ]]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
        double=$((size * 2))
        if [[ "$double" -le 512 ]]; then
            sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
        fi
    done
    if iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null; then
        echo "    Generated AppIcon.icns ($(du -h "$APP_BUNDLE/Contents/Resources/AppIcon.icns" | awk '{print $1}'))"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$PLIST_DST" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST_DST"
    else
        echo "    Warning: could not generate AppIcon.icns"
    fi
    rm -rf "$(dirname "$ICONSET")"
fi

echo "==> Signing app bundle (ad-hoc, no Apple Developer account required)..."
ENTITLEMENTS="$SCRIPT_DIR/MacPhoneMirror.entitlements"
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
echo "    Signed ad-hoc with entitlements"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1

echo "==> Verifying embedded entitlements..."
EMBEDDED_PLIST="$(mktemp)"
codesign -d --entitlements "$EMBEDDED_PLIST" "$APP_BUNDLE" 2>/dev/null

REQUIRED_ENTITLEMENTS=(
    "com.apple.security.network.client"
    "com.apple.security.network.server"
)

MISSING=0
for entitlement in "${REQUIRED_ENTITLEMENTS[@]}"; do
    # codesign writes a human-readable plist ([Dict]/[Key]/[Bool] format), not XML.
    value="$(awk -v target="$entitlement" '
        /\[Key\] / {
            key = $0
            sub(/^.*\[Key\] /, "", key)
            sub(/[ \t]*$/, "", key)
        }
        /\[Bool\] / && key == target {
            value = $0
            sub(/^.*\[Bool\] /, "", value)
            sub(/[ \t]*$/, "", value)
            key = ""
            print value
            found = 1
        }
    ' "$EMBEDDED_PLIST")"

    if [[ "$value" != "true" ]]; then
        echo "Error: Required entitlement '$entitlement' is missing or not true." >&2
        MISSING=1
    else
        echo "    Entitlement '$entitlement' = true"
    fi
done

rm -f "$EMBEDDED_PLIST"

if [[ "$MISSING" != "0" ]]; then
    echo "Error: Signed app is missing required network entitlements." >&2
    exit 1
fi

echo "==> App bundle created at: $APP_BUNDLE"
du -sh "$APP_BUNDLE"
find "$APP_BUNDLE" -type f -exec du -h {} + | sort -hr
