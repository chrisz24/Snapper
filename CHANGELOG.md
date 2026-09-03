# Changelog

Notable changes per release. `scripts/release.sh` reads the section matching the version it is
publishing and uses it as the release notes, so what is written here is what people see on GitHub.

## 0.1.6

- **A text grab no longer produces a screenshot.** ⇧⌘O read the text and then left the captured
  image in the corner with its quick actions, which is a surprise when what you asked for was text.
  The image is no longer kept or previewed by default, and the file it was read from is discarded
  once the text has been taken rather than waiting a week to be cleaned up — recognition works from
  the image in memory, so nothing needed it. **Settings → Text → After reading** turns the preview
  back on for anyone who wants both.

## 0.1.5

- **Reopening after an update now works wherever the app is kept.** 0.1.4 watched the running copy's
  own bundle for the new version, but an update installs to /Applications — so a copy started from
  somewhere else waited for a change that was landing at a different path and never reopened, which
  was the one thing that change existed to fix. It now also watches where the installer puts the
  app, and reopens whichever copy the update actually replaced.

## 0.1.4

- **Snapper reopens itself after installing an update.** Installing used to quit the app and leave
  reopening to you — whether the install had succeeded, failed, or been cancelled. The running copy
  now waits for the new version to actually land and relaunches into it. Cancel the installer and
  nothing changes: the copy you were using carries on.
- **Updates can be installed from the command line**, which matters on a machine where the menu bar
  icon is the thing you cannot see:

  ```
  Snapper.app/Contents/MacOS/Snapper --install-update
  ```

  It runs the same checks as the in-app updater — signed with a Developer ID, signed by the same
  team as your copy, and accepted by macOS — and refuses anything that fails. Add
  `--download-only` to verify and print a `sudo installer` command instead of opening anything.

## 0.1.3

- **The menu bar icon can be switched off**, in Settings → General → Menu bar. Until now there was
  no setting for it, and no way to tell "switched off" apart from macOS having quietly dropped the
  icon for want of room — which it does once enough apps live up there, and almost always on a
  notched display. Both look like an app that failed to start. `--menu-bar-status` answers the other
  half by asking macOS whether it will accept a status item at all. Hiding the icon is safe because
  opening Snapper brings up Settings, which is stated where you switch it off.
- **Markup shapes can be placed by clicking**, not only by dragging. The first click fixes where the
  shape starts, the pointer previews it, and a second click finishes it — so an arrow's tail lands
  exactly where you put it rather than wherever a drag happened to begin. Clicking the same spot
  again abandons it. Dragging works exactly as before, and freehand, text and crop still need it.
- **Markup opens with the tool you used last** instead of resetting to the arrow every time.
- **Closing markup keeps the edits.** Markup used to be a dead end: unless you copied or saved from
  inside the editor, closing the window left you carrying on with the unmarked original. The
  annotations are now flattened into the capture when the editor closes, and the preview comes back
  with them in place, so the quick actions, text recognition and the history entry all work on what
  you just drew. A capture still waiting in scratch is replaced; one you had already saved to your
  own folder is left untouched, and the edited version becomes a new capture instead.

## 0.1.2

- **The shortcut hints under a preview no longer collapse on a tall screenshot.** The row was held
  to the thumbnail's width, and a portrait capture makes that thumbnail narrower than the hints
  themselves — so "Copy", "Save" and "Delete" were squeezed until each wrapped one letter per line,
  and the pill then spilled out of the panel and was cut off. The row keeps its own width now and
  the panel widens to suit it.
- **"Open at login" can be switched on again.** The switch was disabled whenever macOS reported no
  login item registered — which is what it reports for an app that has never registered one. So it
  was greyed out because nothing was registered, and nothing could be registered because it was
  greyed out, while the caption told you to move an app that was already in the right place. If a
  registration is refused you now get the reason macOS gave.
- **Added Uninstall**, in Settings → About. It lists what it will remove — settings, capture
  history, caches, the login item, the app itself — with sizes, before it touches anything. Two
  things it tells you rather than pretending: Screen Recording has to be withdrawn by hand, because
  no app may revoke that for itself, and a copy installed by the package lives in /Applications
  owned by root, so moving it to the Trash needs Finder and your password.
- **Opening Snapper while it is already running opens Settings.** macOS does not start a second
  copy, it notifies the running one — and a menu-bar app has no window to raise, so the app
  appeared to ignore being opened at all.
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
