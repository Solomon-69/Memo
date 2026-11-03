#!/usr/bin/env bash
# Checks the popover arrow joins the body with no seam, light and dark (this app's own look only, never the Mac's).
# Needs a test build (./build.sh, not RELEASE) running. Opens the panel for about a second, silently captured.
# Fails if the arrow and the body beside it differ by more than 4 grey levels, or there is a step across the join.
set -euo pipefail
POST=/private/tmp/tenax-build/post
[ -x "$POST" ] || swiftc "$(dirname "$0")/post.swift" -o "$POST"
fail=0
for L in light dark; do
  rm -f /tmp/memo-popwin.txt
  $POST look:$L; $POST panel; sleep 1.3; $POST popshot:x; sleep 0.8
  ID=$(cut -d' ' -f1 /tmp/memo-popwin.txt)
  screencapture -x -o -l "$ID" "/private/tmp/memo-pop-$L.png"
  $POST close; sleep 0.5
  python3 - "$L" <<'P' || fail=1
import sys
from PIL import Image
L = sys.argv[1]
im = Image.open(f"/private/tmp/memo-pop-{L}.png").convert("L"); w, h = im.size
cx = w // 2
col = [im.getpixel((cx, y)) for y in range(0, 90)]          # down the middle, through the arrow
side = [im.getpixel((cx - 150, y)) for y in range(0, 90)]    # down the body beside the arrow
tip = next(y for y, v in enumerate(col) if v > 0)
top = next(y for y, v in enumerate(side) if v > 0)
rows = range(top + 4, top + 16)                              # the join zone, just under the body's top edge
worst = max(abs(col[y] - side[y]) for y in rows)
step = max(abs(col[y + 1] - col[y]) for y in range(tip + 8, top + 14))
print(f"{L}: arrow vs body worst diff {worst}, biggest step down the join {step}")
sys.exit(0 if worst <= 4 and step <= 4 else 1)
P
done
$POST look:system
[ $fail = 0 ] && echo "ARROW SEAM CHECK PASS" || { echo "ARROW SEAM CHECK FAIL"; exit 1; }
