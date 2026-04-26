#!/usr/bin/env bash
#
# End-to-end smoke test for a published GitHub Release.
#
# Catches every distribution bug we hit between v0.2.0 and v0.2.3:
#   - Resources missing (Bundle.module fatalError on first launch)
#   - Quarantine xattrs blocking launch
#   - Auto-termination after ~30s (App Nap / TAL)
#   - Codesign failures
#
# Usage:
#   scripts/smoke-test-release.sh v0.2.3
#
# Exit codes:
#   0  — all good
#   1  — release missing or zip won't download
#   2  — extracted .app missing required pieces
#   3  — app died within the live-window
#   4  — codesign rejected
#
# This script is what should run before tagging the next release.

set -euo pipefail

VERSION="${1:?usage: $0 v0.2.3}"
VERSION_NO_V="${VERSION#v}"
ZIP="FocusPal-${VERSION}-arm64.zip"
URL="https://github.com/filippello/focuspal/releases/download/${VERSION}/${ZIP}"
WORK="/tmp/focuspal-smoke-${VERSION}"
LIVE_SECONDS="${LIVE_SECONDS:-90}"

echo "==> Smoke testing $VERSION ($URL)"
rm -rf "$WORK" && mkdir -p "$WORK" && cd "$WORK"

if ! curl -fsLO "$URL"; then
    echo "FAIL: could not download $URL" >&2
    exit 1
fi

unzip -q "$ZIP"
APP="$WORK/FocusPal.app"

if [[ ! -d "$APP" ]]; then
    echo "FAIL: zip didn't contain FocusPal.app" >&2
    exit 2
fi

# Required files
[[ -f "$APP/Contents/Info.plist" ]] || { echo "FAIL: missing Info.plist" >&2; exit 2; }
[[ -x "$APP/Contents/MacOS/FocusPal" ]] || { echo "FAIL: missing executable" >&2; exit 2; }
[[ -d "$APP/FocusPal_FocusPal.bundle" ]] || { echo "FAIL: missing resource bundle at .app root (Bundle.module won't find it)" >&2; exit 2; }

echo "==> Bundle structure OK"

# Codesign — adhoc is fine, just check the bundle is consistent
if ! codesign --verify --deep "$APP" 2>&1; then
    echo "FAIL: codesign verification failed" >&2
    exit 4
fi
echo "==> Codesign verify OK"

# Strip quarantine the same way the Cask postflight does, so we can
# actually launch from a script.
xattr -cr "$APP" 2>/dev/null || true

# Kill any prior FocusPal so we can reliably watch the new pid
pkill -f "FocusPal/Contents/MacOS/FocusPal" 2>/dev/null || true
sleep 1

echo "==> Launching $APP"
open "$APP"

# Wait for the process to come up
for i in $(seq 1 10); do
    if pid=$(pgrep -f "FocusPal/Contents/MacOS/FocusPal" | head -1); then
        if [[ -n "$pid" ]]; then break; fi
    fi
    sleep 1
done

if [[ -z "${pid:-}" ]]; then
    echo "FAIL: FocusPal never started" >&2
    exit 3
fi

echo "==> FocusPal launched (pid $pid). Watching for ${LIVE_SECONDS}s of liveness."

deadline=$(( $(date +%s) + LIVE_SECONDS ))
while [[ "$(date +%s)" -lt "$deadline" ]]; do
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "FAIL: pid $pid died at $(date +%H:%M:%S) — auto-termination still happening?" >&2
        exit 3
    fi
    sleep 5
done

echo "==> Still alive after ${LIVE_SECONDS}s. Smoke test passed for $VERSION."
echo "    Cleaning up..."
kill "$pid" 2>/dev/null || true
echo "    Removing $WORK"
cd /
rm -rf "$WORK"
