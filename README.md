# Snapper

[![CI](https://github.com/chrisziko/Snapper/actions/workflows/ci.yml/badge.svg)](https://github.com/chrisziko/Snapper/actions/workflows/ci.yml)

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

Download the latest `.dmg` from [Releases](https://github.com/chrisziko/Snapper/releases), open it,
and drag Snapper to Applications.

The build is signed with a Developer ID and notarized by Apple, so it opens with no Gatekeeper
warning and no right-click-Open dance. On first launch, grant **Screen Recording** under System
Settings → Privacy & Security → Screen & System Audio Recording, then relaunch — macOS only applies
that permission to a fresh launch.

## Requirements

macOS 26 or later. Vision on macOS 26 reports, per line, whether that line was only broken to fit
the width — which is what makes "join wrapped lines into paragraphs" accurate instead of guesswork.

## Building

There is no Xcode on this machine, only Command Line Tools, so the build is SwiftPM plus a Makefile
that assembles the `.app` bundle by hand. No `.xcodeproj` is involved.

```bash
make cert       # one-time: local signing identity, so permissions survive rebuilds
make app        # build + bundle + sign into dist/
make run        # build and launch
make install    # copy to ~/Applications (no admin password needed)
make test       # run the unit suite
make identity   # which of the three signing paths this machine will take, and why
```

The version comes from the `VERSION` file, which is also what the git tag and the DMG name are
built from, so they cannot drift apart.

## Releasing

A build other people can open has to be signed with an Apple-issued **Developer ID** certificate and
**notarized**. Neither ad-hoc nor the self-signed `make cert` identity qualifies: Gatekeeper will
refuse the app on any Mac but the one that built it.

Two one-time setups, both needing a paid Apple Developer Program membership:

```bash
make developer-id     # generate a key + CSR, upload it to Apple, import the certificate
make notary-setup     # store the Apple ID / Team ID / app-specific password notarytool needs
```

`make developer-id` exists because Xcode normally handles the key-and-CSR dance and there is no
Xcode here. It generates the key locally — Apple only ever sees the signing request — prints the
exact portal steps, and imports the issued certificate into its own keychain
(`snapper-distribution.keychain`), kept separate from the self-signed one so `make cert-remove`
cannot take the distribution key with it.

Once both are done, the Makefile picks the Developer ID up automatically and signs with the
hardened runtime and a secure timestamp, which notarization requires.

```bash
make notarize   # notarize dist/Snapper.app and staple the ticket to it
make dmg        # signed disk image with a drag-to-Applications window
make zip        # the same build as a zip
make verify     # what Gatekeeper will conclude on someone else's Mac
make release    # everything: test, build, notarize, package, publish to GitHub
```

`make release VERSION=0.2.0` is the whole thing. It refuses to start on a dirty working tree, an
existing tag, a `VERSION` file that disagrees, a missing certificate or missing notarization
credentials — everything checkable is checked before anything irreversible happens — and asks once
before pushing the tag and publishing.

Stapling is the part worth understanding: notarization records a ticket on Apple's servers, and
Gatekeeper will fetch it over the network, but a machine that is offline or behind a filter cannot.
Stapling writes the ticket into the bundle so the check passes without a network. The app is
notarized and stapled *first*, and the DMG and zip are then cut from the stapled bundle — done the
other way round, the copy inside the DMG would carry no ticket.

Releases are cut locally, not in CI, so the Developer ID private key never leaves this machine and
is never uploaded to GitHub as a secret. CI builds, tests, and assembles an ad-hoc-signed bundle.

### Diagnostics

Three self-tests run the real code paths and print what they find:

```bash
dist/Snapper.app/Contents/MacOS/Snapper --ocr-test      # renders a page, reads it back in all three modes
dist/Snapper.app/Contents/MacOS/Snapper --preview-test  # preview placement, countdown, key grab/release
dist/Snapper.app/Contents/MacOS/Snapper --self-test     # full capture pipeline (needs Screen Recording)
dist/Snapper.app/Contents/MacOS/Snapper --update-check  # live check against the GitHub Releases API
```

The first two need no permissions. Run the binary from **inside the bundle** as shown — that is what
makes macOS attribute the Screen Recording check to the app rather than to your terminal.

## Screen Recording permission

Snapper cannot capture anything without it. macOS will prompt on first launch; if you miss the
prompt, open **System Settings → Privacy & Security → Screen & System Audio Recording** and enable
Snapper. **A newly granted permission only takes effect after the app is relaunched.**

### Keeping the permission across rebuilds

macOS ties this permission to the app's *designated requirement*. An ad-hoc signature's requirement
is a raw `cdhash`, which changes with every build — so each rebuild looks like a brand new app and
the prompt comes back.

`make cert` fixes this once and for all:

```bash
make cert       # create a local self-signed code-signing identity
make install    # rebuild, signed with it
```

The requirement then becomes `identifier "com.zikopoulos.snapper" and certificate root H"..."`,
which is pinned to the certificate rather than the binary, so it does not change when you rebuild.
Once the identity exists, `make` picks it up automatically — nothing to remember.

What the script actually does, and why:

- Generates an RSA key and a self-signed certificate with the `codeSigning` extended key usage,
  valid for ten years.
- Puts it in a **dedicated keychain** (`snapper-signing.keychain`), not your login keychain. This
  is the important part: a key in the login keychain triggers a *"codesign wants to use your key"*
  dialog that blocks the build until someone clicks it. Because the script creates this keychain,
  it knows its password and can authorise the key's access list up front, so builds never stop to
  ask. The password is generated locally, stored `chmod 600` under
  `~/Library/Application Support/com.zikopoulos.snapper/signing/`, and unlocks nothing but this
  one keychain.
- Adds the keychain to your search list, leaving the existing entries alone.

The certificate is a local build artefact, not a trust anchor. It is not added to the System
keychain, is not marked as a trusted root, and vouches for nothing beyond keeping this app's
signature stable on this machine. Other software is unaffected.

To undo it completely:

```bash
make cert-remove    # deletes the keychain and the password file; builds fall back to ad-hoc
```

To start the permission state over: `make reset-permissions`.

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

## Where captures go

**Captures are not saved automatically by default.** A screenshot lives in a scratch folder and
appears in the preview, and it is yours to decide what to do with — `⌘C` to copy it, `⌘S` to save
it somewhere, or right-click for the rest. Nothing lands on your Desktop unless you ask for it.

Unsaved captures stay reachable from **Recent Captures** in the menu bar, and are cleared out after
a week. Turn on *Save every capture automatically* in Capture settings for the traditional
everything-on-the-Desktop behaviour.

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

## Updates

**Menu bar → Check for Updates…** asks GitHub whether a newer release has been published, and
Snapper also asks once a day on its own. Nothing is downloaded or installed on your behalf: if
there is an update, you get its version, size and release notes, and the choice of **Download**,
**Later**, or **Skip This Version**. Download opens the disk image in your browser — a menu bar app
cannot replace its own bundle while it is running, so pretending otherwise would just be a worse
version of dragging it to Applications yourself.

What it actually does is one unauthenticated `GET` to the public Releases API. No token, no
account, nothing about your machine beyond what any HTTP request carries. It reads the whole release
list rather than GitHub's `/releases/latest`, because "latest" there means *most recently
published*, not *highest version* — re-publishing an old tag would otherwise look like a downgrade
to everyone who checked.

**About** in Settings has the switches: automatic checks on or off, whether pre-releases count, when
it last checked, and a way to un-skip a version you skipped. Pre-releases are excluded by default,
so publishing a beta never nags a stable install.

Verify the whole path from the command line without waiting to be prompted:

```bash
dist/Snapper.app/Contents/MacOS/Snapper --update-check
```

It prints the endpoint, the installed version, what it found, and which asset "Download" would open.

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
app, or by macOS itself.

That last case is worth explaining, because it is a silent trap. `RegisterEventHotKey` *accepts* a
combination macOS already owns; the shortcut then simply never fires, because the system handles it
first. So Snapper reads the system's own shortcut table (`com.apple.symbolichotkeys`) and tells you
outright. It also distinguishes a shortcut that is genuinely active from one you have already
switched off — a combination missing from that table is still at its default and therefore live,
whereas one present but disabled is yours to take.

The three capture shortcuts default to **⌘⇧3**, **⌘⇧4** and **⌘⇧5** — the same combinations macOS
uses for its own screenshots. That works only where the system's versions have been switched off in
**Keyboard → Keyboard Shortcuts → Screenshots**. Where they are still active, macOS handles them
first and Snapper never sees the keystroke.

Because that failure is completely silent, Snapper checks the system's shortcut table rather than
letting you find out the hard way. **A setup window on first launch** shows exactly which shortcuts
are blocked and by what, and offers three ways forward: open Keyboard Settings to free them up, or
switch Snapper to **⌥⌘3 / ⌥⌘4 / ⌥⌘5** which macOS does not use, or skip and sort it out later.
It is entirely skippable, and reachable again from **Set Up Snapper…** in the menu bar or
**Settings → Shortcuts → Run Setup Again**.

Snapper deliberately never rewrites the system's shortcut preferences on your behalf — doing so is
fragile and requires restarting `cfprefsd`.

## License

MIT — see [LICENSE](LICENSE).
