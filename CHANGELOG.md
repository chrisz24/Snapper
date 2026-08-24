# Changelog

Notable changes per release. `scripts/release.sh` reads the section matching the version it is
publishing and uses it as the release notes, so what is written here is what people see on GitHub.

## Unreleased

- **Updates install in place.** "Install" downloads the package, checks it is signed by the same
  developer as your copy and accepted by macOS, then hands it to the system installer — no browser,
  no manual download. macOS still asks for your password, because the app lives in /Applications and
  only the system can replace it.

## 0.1.1

- **Setup no longer skips itself when you quit to grant Screen Recording.** macOS only applies that
  permission to a new launch, so quitting is a step in the middle of setup — but the app treated the
  window closing as "setup finished" and came back with the remaining steps reachable only from the
  menu bar.
- **Added a "Quit & Reopen" button** to the Screen Recording step, so the required restart is one
  click instead of something you have to work out and do by hand. Setup resumes where it left off.
- **`--self-test` no longer changes your settings.** It pointed the save folder at its own sandbox
  and muted the shutter, and left both that way — so running a diagnostic quietly reconfigured where
  your screenshots went.
- Added `make reset-settings`, which clears stored preferences so the next launch behaves like a
  genuine first run. Uninstalling the app never did this: preferences live in your home folder, not
  in the app.

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
