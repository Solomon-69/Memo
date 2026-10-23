#!/usr/bin/env bash
# build.sh: compile Memo.app with swiftc (no Xcode project), sign, install to ~/Applications.
#   ./build.sh               build + install + relaunch in the background
#   ./build.sh --regen-icon  redraw the icon first
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=/private/tmp/tenax-build
TARGET="${TARGET:-arm64-apple-macos14.0}"
mkdir -p "$OUT"
if [ "${1:-}" = "--regen-icon" ] || [ ! -f "$REPO/assets/Assets.car" ]; then
  # Draw the art, wrap it in an Icon Composer bundle, compile with actool.
  # actool gives macOS 26 its layered icon (with the system's own dark and tinted looks)
  # plus a classic .icns for older macOS.
  swiftc -O -framework AppKit "$REPO/make-icon.swift" -o "$OUT/mkicon"
  rm -rf "$OUT/icon"; "$OUT/mkicon" "$OUT/icon"
  ICON="$OUT/icon/Memo.icon"; mkdir -p "$ICON/Assets"
  cp "$OUT/icon/art-light.png" "$OUT/icon/art-dark.png" "$ICON/Assets/"
  cp "$REPO/assets/icon.json" "$ICON/icon.json"
  rm -rf "$OUT/icon/car"; mkdir -p "$OUT/icon/car"
  xcrun actool "$ICON" --compile "$OUT/icon/car" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon Memo --output-partial-info-plist "$OUT/icon/partial.plist" >/dev/null
  cp "$OUT/icon/car/Assets.car" "$OUT/icon/car/Memo.icns" "$REPO/assets/"
  cp "$OUT/icon/Memo-1024.png" "$OUT/icon/Memo-1024-dark.png" "$REPO/assets/"
fi
# Test hook only in test builds (RELEASE=1 leaves it out).
FLAGS=(-O); [ "${RELEASE:-0}" = "1" ] || FLAGS+=(-D TENAX_TEST)
swiftc -O -parse-as-library -target "$TARGET" "${FLAGS[@]}" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement -framework Carbon -lsqlite3 \
  "$REPO"/Sources/*.swift -o "$OUT/Memo"
APP="$OUT/Memo.app"; rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$REPO/Info.plist" "$APP/Contents/"; cp "$OUT/Memo" "$APP/Contents/MacOS/"
cp "$REPO/assets/Assets.car" "$REPO/assets/Memo.icns" "$APP/Contents/Resources/"
xattr -cr "$APP"
# Your own signing identity can go in a .signing file (kept out of git); otherwise ad-hoc.
SIGN_ID="$(cat "$REPO/.signing" 2>/dev/null || true)"
[ -n "$SIGN_ID" ] && codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP"
pkill -x Tenax 2>/dev/null || true
pkill -x Memo 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/Tenax.app   # the app's first name; its history moves over on first launch
rm -rf ~/Applications/Memo.app; ditto "$APP" ~/Applications/Memo.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/Memo.app
open -g ~/Applications/Memo.app
echo "installed ~/Applications/Memo.app"
