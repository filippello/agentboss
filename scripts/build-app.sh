#!/usr/bin/env bash
#
# Build a distributable FocusPal.app bundle from the SPM release binary.
#
# Output: dist/FocusPal.app
#
# Usage:
#   scripts/build-app.sh                # builds for the host arch
#   scripts/build-app.sh --skip-build   # reuse the existing release build
#
# The resulting .app is unsigned, so when first launched on another Mac
# the user has to right-click → Open. The README documents that.

set -euo pipefail

# Resolve the repo root (the directory containing this script's parent).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="FocusPal"
BUNDLE_ID="com.filippello.focuspal"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Pull version from git tag if we're on one, otherwise use a -dev suffix.
VERSION="${FOCUSPAL_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo "0.2.0-dev")}"
VERSION="${VERSION#v}"   # strip a leading "v"

if [[ "${1:-}" != "--skip-build" ]]; then
    echo "==> swift build -c release"
    swift build -c release
fi

BIN_PATH="$(swift build -c release --show-bin-path)"
EXECUTABLE="$BIN_PATH/$APP_NAME"
RESOURCE_BUNDLE="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "error: executable not found at $EXECUTABLE" >&2
    exit 1
fi
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "error: resource bundle not found at $RESOURCE_BUNDLE" >&2
    exit 1
fi

echo "==> Building $APP_DIR (v$VERSION)"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Binary
cp "$EXECUTABLE" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# SPM resource bundle (sprites + default config). Bundle.module expects to
# find it as a sub-bundle named "<TargetName>_<TargetName>.bundle" inside
# the main bundle's Resources, so we copy it verbatim.
cp -R "$RESOURCE_BUNDLE" "$RESOURCES/"

# Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>      <string>en</string>
  <key>CFBundleDisplayName</key>            <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>             <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>             <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>  <string>6.0</string>
  <key>CFBundleName</key>                   <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>            <string>APPL</string>
  <key>CFBundleShortVersionString</key>     <string>$VERSION</string>
  <key>CFBundleVersion</key>                <string>$VERSION</string>
  <key>LSApplicationCategoryType</key>      <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>         <string>13.0</string>
  <key>LSUIElement</key>                    <true/>
  <key>NSHighResolutionCapable</key>        <true/>
  <key>NSHumanReadableCopyright</key>       <string>© 2026 Federico Filippello — MIT</string>
  <!-- FocusPal is a long-running menu-bar agent — opt out of macOS App Nap
       + Automatic/Sudden Termination so the OS can't kill the frog while
       it's waiting for Claude Code events. -->
  <key>NSSupportsAutomaticTermination</key> <false/>
  <key>NSSupportsSuddenTermination</key>    <false/>
</dict>
</plist>
PLIST

# Strip extended attributes that Gatekeeper sometimes uses to mark unsigned
# downloads. Keeps the right-click → Open dance one step shorter for users
# building from source.
xattr -cr "$APP_DIR" 2>/dev/null || true

echo "==> Done: $APP_DIR"
echo
du -sh "$APP_DIR"
