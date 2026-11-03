#!/usr/bin/env bash
# Show in Dock check, silent: offscreen light+dark snap of Settings, then a test build and a read-back of the
# activation policy (accessory -> regular -> accessory) plus a Dock-click (reopen) that opens the panel.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK=/tmp/macapps-heavy.lock
for _ in $(seq 120); do
  grep -q CRITICAL ~/.claude/chat-priority/LOAD 2>/dev/null || { mkdir "$LOCK" 2>/dev/null && break; }
  sleep 5
done
[ -d "$LOCK" ] || { echo "no lock"; exit 1; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
POST=/private/tmp/tenax-build/post
mkdir -p /private/tmp/tenax-build
"$REPO/QA/snap.sh" /private/tmp/memo-dock-snap 2>&1 | tail -3
"$REPO/build.sh" 2>&1 | tail -3
[ -x "$POST" ] || swiftc "$REPO/QA/post.swift" -o "$POST"
sleep 3
rd() { rm -f /tmp/memo-policy.txt; "$POST" policy; for _ in $(seq 20); do [ -s /tmp/memo-policy.txt ] && break; sleep 0.25; done; cat /tmp/memo-policy.txt; echo; }
echo "start:   $(rd)"
"$POST" dock:1; sleep 0.8; echo "dock on: $(rd)"
"$POST" close; sleep 0.4; "$POST" reopen; sleep 0.8; echo "reopen:  $(rd)"
"$POST" close; "$POST" dock:0; sleep 0.8; echo "dock off: $(rd)"
"$POST" close
echo DONE
