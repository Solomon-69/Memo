#!/usr/bin/env bash
# release.sh: Developer ID sign, notarize, staple; zip + dmg + checksums in ./dist. Windows zip passed as $1.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID="Developer ID Application: Yael Michal Dredzen (QJ3359CB4R)"
OUT=/private/tmp/tenax-build; APP="$OUT/Memo.app"
rm -rf "$REPO/dist"; mkdir -p "$REPO/dist"
RELEASE=1 "$REPO/build.sh"
codesign --force --deep --options runtime --timestamp --sign "$ID" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$OUT/submit.zip"
xcrun notarytool submit "$OUT/submit.zip" --keychain-profile notary --wait
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$REPO/dist/Memo-mac.zip"
rm -rf "$OUT/dmg"; mkdir -p "$OUT/dmg"; cp -R "$APP" "$OUT/dmg/"; ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Memo" -srcfolder "$OUT/dmg" -ov -format UDZO "$REPO/dist/Memo.dmg" >/dev/null
codesign --force --timestamp --sign "$ID" "$REPO/dist/Memo.dmg"
xcrun notarytool submit "$REPO/dist/Memo.dmg" --keychain-profile notary --wait
xcrun stapler staple "$REPO/dist/Memo.dmg"
[ -n "${1:-}" ] && cp "$1" "$REPO/dist/Memo-windows.zip"
( cd "$REPO/dist" && shasum -a 256 Memo.dmg Memo-mac.zip $( [ -n "${1:-}" ] && echo Memo-windows.zip ) > SHA256SUMS.txt )
spctl -a -vvv -t install "$REPO/dist/Memo.dmg" 2>&1 | head -3 || true
echo "DONE $REPO/dist"
