# Tenax QA log

## Round 1 (22 Oct 2026)
- Logic tests (QA/test.sh, throwaway folder): 39/39 pass; broken database recovers.
- Off-screen snapshots (QA/snap.sh): popover, search, empty + paused, Settings, light and dark.
- Live hook tests on the running app: record text/link/colour, link cleaned (utm_source, fbclid removed), pin, reorder pins, search, plain paste, Markdown paste, pause (nothing recorded), resume, delete, quick paste number 2. All pass.
- Live screenshot: popover arrow sits under the icon, pill highlight, light look.
- Problems found:
  1. Fuzzy search too loose ("lun" matched scattered letters in long text). Fixed: letters must sit close together.
  2. "Pinned" heading scrolled out of view on open. Fixed: scroll to a top marker.
  3. Row under the pointer stole the selection on open. Fixed: only a real mouse move selects.
  4. Settings window opened behind the active app. Fixed: bring it to the front (it is a deliberate request).
  5. Test note: synthetic key presses from the shell are dropped (no Accessibility for the shell), so the global shortcut is checked by registration + log, not by a fake key press.
