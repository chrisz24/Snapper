<img src="Resources/AppIcon.png" width="116" align="right" alt="">

# Snapper

A menu bar screenshot utility for macOS that keeps the familiar capture-and-preview behaviour and
adds the two things missing from it: **text recognition from a selection**, and **quick actions that
work on the capture while its preview is still on screen**.

## What it does

- **⌘⇧4 / ⌘⇧5 / ⌘⇧3** — capture a selection, a window, or the whole screen. The selection UI is
  macOS's own, so the crosshair, magnifier loupe, live dimension readout, space-to-toggle-window and
  Esc-to-cancel all behave exactly as you already expect.
- **⇧⌘O** — drag a selection and get its **text** on the clipboard.
- **Quick actions** — while the preview thumbnail is up, `⌘C` copies it and dismisses the preview,
  `⌘S` opens a save panel, `⌘O` reads its text, `⌘E` opens markup, `⌘⌫` discards it.
- **The preview itself** — click it to open, drag it out to drop the file elsewhere, hit the **×**
  in its corner to dismiss it, or **right-click for the full menu** of everything the shortcuts do.
  Choosing an item closes the preview. The countdown pauses while you hover or while the menu is
  open, so it never disappears mid-decision.
- **Markup** — arrows, boxes, ellipses, freehand, highlighter, text, crop, and **pixelated
  redaction** for anything sensitive.
- **History** — recent captures stay in the menu bar so you can copy, re-read, or mark them up after
  the preview has gone.

## Installing

Download the latest `.pkg` from [Releases](https://github.com/chrisz24/Snapper/releases) and open
it. The installer puts Snapper in your Applications folder — no dragging, and no chance of running it
from a mounted disk image by mistake. macOS will ask for your password, as it does for any installer.

Snapper is signed and notarized by Apple, so it opens with no Gatekeeper warning and no
right-click-Open dance.

Requires **macOS 26 or later**, on Apple silicon.

## Screen Recording permission

Snapper cannot capture anything without it. macOS prompts on first launch; if you miss the prompt,
open **System Settings → Privacy & Security → Screen & System Audio Recording** and switch Snapper
on. **A newly granted permission only takes effect after the app is relaunched.**

## Where captures go

**Captures are not saved automatically by default.** A screenshot appears in the preview and it is
yours to decide what to do with — `⌘C` to copy it, `⌘S` to save it somewhere, or right-click for the
rest. Nothing lands on your Desktop unless you ask for it.

Unsaved captures stay reachable from **Recent Captures** in the menu bar, and are cleared out after
a week. Turn on *Save every capture automatically* in Capture settings for the traditional
everything-on-the-Desktop behaviour.

## The ⌘C trade-off, stated plainly

For a shortcut like `⌘C` to act on the preview from wherever you happen to be, Snapper has to take
that key system-wide — so **while a preview is on screen, `⌘C` in another app copies the screenshot
instead of your selection.** This is deliberate, and it is bounded:

- it lasts only as long as the preview (5 seconds by default),
- the preview shows you which shortcuts are currently taken over,
- and the keys are handed straight back the moment you click, switch apps, or the preview expires.

If you would rather never risk it, **Settings → Quick Actions** offers *Only while pointing at the
preview*, which never touches your shortcuts, or you can rebind the actions to combinations nothing
else uses.

## Settings

| Tab | What's there |
| --- | --- |
| General | Preview on/off, corner, **how long it stays** (also the quick-action window), size, sounds, open at login |
| Capture | Save folder, filename template, format, auto-copy, shadow, pointer, delay, history |
| Text | **Line breaks: preserve / join wrapped lines / single line**, de-hyphenation, languages, quality, sharpening for small selections, review-before-copy |
| Quick Actions | Global vs hover-only, release on app switch, per-action shortcut and on/off |
| Shortcuts | The five global shortcuts, plus a link to free up macOS's own ⌘⇧3/4/5 |
| About | Version, Screen Recording status, and update checking |

### Line break modes

- **Preserve line breaks** — text comes back laid out as it appeared on screen.
- **Join wrapped lines into paragraphs** *(default)* — lines broken only to fit the width are
  rejoined into flowing prose, real paragraph breaks are kept, headings stay on their own line, and
  words split across a break are made whole again.
- **Single line** — everything on one line. Useful for URLs, IDs, and serial numbers.

## Recording your own shortcuts

Every action is rebindable. **Settings → Shortcuts** covers the five global ones, and
**Settings → Quick Actions** covers the ones that act on a preview. The menu bar also has a
**Keyboard Shortcuts…** item that opens straight to the right tab.

Click a shortcut to record a new one:

- press any combination with at least one modifier,
- **Esc** cancels and leaves the old one alone,
- **Delete** clears it back to the default,
- the **×** beside the field does the same with the mouse.

Snapper warns you when a combination is already spoken for — by another Snapper action, by another
app, or by macOS itself. That last case matters, because macOS wins silently: it handles the
keystroke first and Snapper simply never sees it. Rather than let you discover that the hard way,
Snapper checks the system's own shortcut list and tells you outright.

The three capture shortcuts default to **⌘⇧3**, **⌘⇧4** and **⌘⇧5** — the same combinations macOS
uses for its own screenshots. Those work only where the system's versions have been switched off in
**Keyboard → Keyboard Shortcuts → Screenshots**.

So **a setup window on first launch** shows exactly which shortcuts are blocked and by what, and
offers three ways forward: open Keyboard Settings to free them up, switch Snapper to
**⌥⌘3 / ⌥⌘4 / ⌥⌘5** which macOS does not use, or skip and sort it out later. It is entirely
skippable, and reachable again from **Set Up Snapper…** in the menu bar or
**Settings → Shortcuts → Run Setup Again**.

Snapper never rewrites your system shortcut settings on your behalf.

## Updates

**Menu bar → Check for Updates…** asks whether a newer release has been published, and Snapper also
checks once a day on its own. Nothing is downloaded or installed on your behalf: if there is an
update you get its version, size and release notes, and the choice of **Install**, **Later**, or
**Skip This Version**.

**Install** does it in place — no trip to a browser and no hunting for a downloaded file. Snapper
fetches the installer, checks it is signed by the same developer as your copy and that macOS accepts
it, then hands it to the system installer. macOS asks for your password at that point, as it does
for any installer, because the app lives in `/Applications` and only the system can replace it.

The check sends nothing about you or your machine, and needs no account. **About** in Settings has
the switches: automatic checks on or off, whether pre-releases count, when it last checked, and a way
to un-skip a version you skipped. Pre-releases are excluded by default, so a published beta never
nags a stable install.

## Building from source

See **[BUILDING.md](BUILDING.md)**.

## License

MIT — see [LICENSE](LICENSE).
