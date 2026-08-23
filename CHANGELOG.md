# Changelog

Notable changes per release. `scripts/release.sh` reads the section matching the version it is
publishing and uses it as the release notes, so what is written here is what people see on GitHub.

## 0.1.0

First public release.

- **Capture** — selection, window, and full screen, using macOS's own selection UI so the
  crosshair, loupe, live dimensions, space-to-toggle-window and Esc-to-cancel all behave as
  expected.
- **Text recognition** — drag a selection and get its text on the clipboard, with three line-break
  modes including wrap-aware paragraph rejoining.
- **Quick actions** — copy, save, read text, mark up, or discard a capture while its preview is
  still on screen.
- **Markup** — arrows, boxes, ellipses, freehand, highlighter, text, crop, and pixelated redaction.
- **History** — recent captures stay reachable from the menu bar for a week.
- **Check for Updates** — asks GitHub once a day whether a newer release exists; nothing is
  downloaded without you choosing to.
