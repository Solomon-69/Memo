#!/usr/bin/env bash
# Builds and runs the off-screen snapshot harness. Usage: QA/snap.sh [outdir]
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-/private/tmp/tenax-snap}"
SRC=()
for f in "$REPO"/Sources/*.swift; do [ "$(basename "$f")" = App.swift ] || SRC+=("$f"); done
swiftc -O -target arm64-apple-macos14.0 -framework AppKit -framework SwiftUI -framework ServiceManagement -framework Carbon -lsqlite3 \
  "${SRC[@]}" "$REPO/QA/snapshot.swift" -o /private/tmp/tenax-build/snap 2>&1 | grep -E "error" || true
/private/tmp/tenax-build/snap "$OUT"
