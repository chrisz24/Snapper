# Building, signing and releasing Snapper

Everything technical that used to live in `README.md`. For what the app does and how to use it, see
[README.md](README.md); for setting the project up on a different Mac, see [MIGRATION.md](MIGRATION.md).

## Requirements

- macOS 26 or later. Vision on macOS 26 reports, per line, whether that line was only broken to fit
  the width — which is what makes "join wrapped lines into paragraphs" accurate instead of guesswork.
- Command Line Tools: `xcode-select --install`.

Xcode is not needed and is not used. The build is SwiftPM plus a Makefile that assembles the `.app`
bundle by hand; no `.xcodeproj` is involved.

## Building

```bash
make cert       # one-time: local signing identity, so permissions survive rebuilds
make app        # build + bundle + sign into dist/
make run        # build and launch
make install    # copy to ~/Applications (no admin password needed)
make test       # run the unit suite
make identity   # which of the three signing paths this machine will take, and why
```

The version comes from the `VERSION` file, which is also what the git tag and the package name are
built from, so they cannot drift apart.

## Diagnostics

Self-tests that run the real code paths and print what they find:

```bash
dist/Snapper.app/Contents/MacOS/Snapper --ocr-test      # renders a page, reads it back in all three modes
dist/Snapper.app/Contents/MacOS/Snapper --preview-test  # preview placement, countdown, key grab/release
dist/Snapper.app/Contents/MacOS/Snapper --settings-test # settings window, shortcut recorder
dist/Snapper.app/Contents/MacOS/Snapper --self-test     # full capture pipeline (needs Screen Recording)
dist/Snapper.app/Contents/MacOS/Snapper --update-check  # live check against the GitHub Releases API
```

Only `--self-test` needs permissions. Run the binary from **inside the bundle** as shown — that is
what makes macOS attribute the Screen Recording check to the app rather than to your terminal.

`--update-check` prints the endpoint, the installed version, what it found, and which asset
"Download" would open. Other diagnostics: `--dump-shortcuts`, `--preview-demo N`,
`--settings-demo <tab> N`, `--setup-demo N [--blocked]`.

## Keeping Screen Recording permission across rebuilds

macOS ties this permission to the app's *designated requirement*. An ad-hoc signature's requirement
is a raw `cdhash`, which changes with every build — so each rebuild looks like a brand new app and
the prompt comes back.

Signing with a stable certificate fixes it. **A Developer ID (below) is the real answer**, since its
requirement is anchored to Apple and pinned to the team, and it is what you need for distribution
anyway. `make cert` is the fallback when you have no membership:

```bash
make cert       # create a local self-signed code-signing identity
make install    # rebuild, signed with it
```

Once either identity exists, `make` picks it up automatically — nothing to remember.

What `make cert` actually does, and why:

- Generates an RSA key and a self-signed certificate with the `codeSigning` extended key usage,
  valid for ten years.
- Puts it in a **dedicated keychain** (`snapper-signing.keychain`), not your login keychain. This is
  the important part: a key in the login keychain triggers a *"codesign wants to use your key"*
  dialog that blocks the build until someone clicks it. Because the script creates this keychain, it
  knows its password and can authorise the key's access list up front, so builds never stop to ask.
  The password is generated locally, stored `chmod 600` under
  `~/Library/Application Support/com.zikopoulos.snapper/signing/`, and unlocks nothing but this one
  keychain.
- Adds the keychain to your search list, leaving the existing entries alone.

That certificate is a local build artefact, not a trust anchor. It is not added to the System
keychain, is not marked as a trusted root, and vouches for nothing beyond keeping this app's
signature stable on this machine. Other software is unaffected.

To undo it: `make cert-remove`. To start the permission state over: `make reset-permissions`.

## Releasing

A build other people can open has to be signed with an Apple-issued **Developer ID** certificate and
**notarized**. Neither ad-hoc nor the self-signed `make cert` identity qualifies: Gatekeeper will
refuse the app on any Mac but the one that built it.

Three one-time setups, all needing a paid Apple Developer Program membership:

```bash
make developer-id     # "Developer ID Application" — signs the app
make installer-id     # "Developer ID Installer"   — signs the .pkg
make notary-setup     # store the credentials notarytool authenticates with
```

The two certificates are **different types from the same account**, and neither can do the other's
job: a certificate issued for the app cannot sign the installer. Each needs its own key and its own
signing request, which is why there are two commands. `make identity` shows which of the two you
have.

`make developer-id` exists because Xcode normally handles the key-and-CSR dance and there is no
Xcode here. It generates the key locally — Apple only ever sees the signing request — prints the
exact portal steps, and imports the issued certificate into its own keychain
(`snapper-distribution.keychain`), kept separate from the self-signed one so `make cert-remove`
cannot take the distribution key with it.

`make notary-setup` offers two ways to authenticate. An **App Store Connect API key** — a `.p8`
file, a Key ID and an Issuer ID — involves no password at all, is revocable on its own, and is the
only option that works unattended; that is the one to pick. An **app-specific password** against
your Apple ID is the fallback if you have not made an API key before. Either way the secret goes
straight into `notarytool store-credentials`, which keeps it in the login keychain: nothing lands in
this repo, and nothing is passed on a command line where `ps` would show it.

Certificate issuance is deliberately *not* automated through the App Store Connect API even though
an endpoint exists for it. `POST /v1/certificates` has been returning `FORBIDDEN_ERROR` since around
January 2026, and the API rejects `DEVELOPER_ID_APPLICATION_G2` — the type Apple's own portal now
forces you to choose. Uploading a CSR by hand is the path that works.

Once both are done, the Makefile picks the Developer ID up automatically and signs with the hardened
runtime and a secure timestamp, which notarization requires.

```bash
make notarize   # notarize dist/Snapper.app and staple the ticket to it
make pkg        # signed installer package
make zip        # the same build as a zip
make verify     # what Gatekeeper will conclude on someone else's Mac
make release    # everything: test, build, notarize, package, publish to GitHub
```

`make release VERSION=0.2.0` is the whole thing. It refuses to start on a dirty working tree, an
existing tag, a `VERSION` file that disagrees, a missing certificate or missing notarization
credentials — everything checkable is checked before anything irreversible happens — and asks once
before pushing the tag and publishing.

Release notes come from the matching section of [CHANGELOG.md](CHANGELOG.md) if there is one, and
from the commit log since the previous tag if there is not. A version with a suffix — `0.3.0-beta.1`
— is published as a pre-release, which is what the updater's "Include pre-releases" setting filters
on.

### Why stapling matters

Notarization records a ticket on Apple's servers, and Gatekeeper will fetch it over the network — but
a machine that is offline or behind a filter cannot. Stapling writes the ticket into the bundle so
the check passes without a network.

The app is notarized and stapled *first*, and the package and zip are then built from the stapled
bundle. Done the other way round, the copy inside the installer would carry no ticket.

Note that the hardened runtime applies to the app but not to the package: it is a property of
executable code, and `productbuild` will not set that flag on a container. A `.pkg` does still need a
secure timestamp to be notarizable.

### The one line in make-pkg.sh that matters most

`pkgbuild` defaults `BundleIsRelocatable` to **true**, which makes Installer hunt for an existing
copy of the app *anywhere on the disk* and update that instead of installing to `/Applications`.
Anyone with a build in `~/Applications` — which `make install` puts there — would have it silently
overwritten, and nothing would appear where they expected. `make-pkg.sh` pins it to false.

The distribution file also declares the OS floor from the bundle's `LSMinimumSystemVersion` and the
architectures actually present in the binary. Without those, Installer happily installs on an older
macOS or an Intel Mac and the app simply never launches.

### Why releases are not cut in CI

The Developer ID private key never leaves this machine and is never uploaded to GitHub as a secret.
CI builds, runs the tests, and assembles an ad-hoc-signed bundle to prove the bundle assembles and
signs; releases are made locally with `make release`.

## How the updater works

One unauthenticated `GET` to the public Releases API — no token, no account, nothing about the
machine beyond what any HTTP request carries.

The download it offers is the `.pkg`, falling back to a `.dmg` and then a `.zip` — the `.dmg` entry
is kept so that releases published before the switch to an installer still resolve to a real
download instead of the release page.

It reads the whole release list rather than GitHub's `/releases/latest`, because "latest" there means
*most recently published*, not *highest version* — re-publishing an old tag would otherwise look like
a downgrade to everyone who checked. `UpdateResolver` picks the highest version instead, and
`AppVersion` does the comparison, because string ordering puts `0.10.0` below `0.9.9` and even a
numeric string compare mishandles pre-release suffixes.

Download opens the disk image in the browser rather than fetching it in-process: a menu bar app
cannot replace its own bundle while running, so anything else would be a worse version of dragging
it to Applications yourself.

The repository the updater queries is set by two constants in
[`AppInfo.swift`](Sources/SnapperKit/App/AppInfo.swift) — a fork only has to change those.

## Tests

```bash
make test
```

100 tests. Command Line Tools ship neither XCTest nor swift-testing, so the suite is an ordinary
executable target with a small built-in harness in `Tests/SnapperTests/Harness.swift`. Everything
under test is public API, so no `@testable` import is needed.
