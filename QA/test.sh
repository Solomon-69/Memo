#!/usr/bin/env bash
# Logic tests against a throwaway history folder, plus a broken-database recovery check.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC=()
for f in "$REPO"/Sources/*.swift; do case "$(basename "$f")" in App.swift|Intro.swift|PopoverView.swift|SettingsView.swift|ChipDrumPicker.swift|SmoothSwitch.swift|Glyph.swift) ;; *) SRC+=("$f");; esac; done
swiftc -O -target arm64-apple-macos14.0 -framework AppKit -framework Carbon -framework SwiftUI -lsqlite3 "${SRC[@]}" "$REPO/QA/logic-tests.swift" -o /private/tmp/tenax-build/tests 2>&1 | grep error || true
HOME_DIR=$(mktemp -d /private/tmp/tenax-test.XXXX)
TENAX_HOME="$HOME_DIR" /private/tmp/tenax-build/tests
# Broken database: must start fresh instead of showing a blank list forever.
B=$(mktemp -d /private/tmp/tenax-broken.XXXX); echo "this is not a database" > "$B/history.sqlite"
TENAX_HOME="$B" /private/tmp/tenax-build/tests >/dev/null 2>&1 || true
ls "$B" | grep -q "history-broken-" && echo "broken database recovered: PASS" || echo "broken database recovered: FAIL"
rm -rf "$HOME_DIR" "$B"
