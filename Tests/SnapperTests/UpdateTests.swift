import Foundation
import SnapperKit

enum UpdateTests {

    /// A trimmed-down copy of what `GET /repos/:owner/:repo/releases` actually returns, including
    /// the parts that have to be ignored: a draft, an unparseable tag, a checksum asset, and a
    /// release created most recently but numbered lowest.
    private static let feed = """
    [
      {
        "tag_name": "v0.9.0",
        "name": "Snapper 0.9.0",
        "body": "Newest by date, lowest by number.",
        "html_url": "https://github.com/chrisz24/Snapper/releases/tag/v0.9.0",
        "draft": false,
        "prerelease": false,
        "published_at": "2026-08-20T10:00:00Z",
        "assets": [
          { "name": "Snapper-0.9.0.dmg", "browser_download_url": "https://example.invalid/0.9.0.dmg", "size": 5242880, "state": "uploaded" }
        ]
      },
      {
        "tag_name": "v1.2.0",
        "name": "Snapper 1.2.0",
        "body": "Real latest.",
        "html_url": "https://github.com/chrisz24/Snapper/releases/tag/v1.2.0",
        "draft": false,
        "prerelease": false,
        "published_at": "2026-08-01T10:00:00Z",
        "assets": [
          { "name": "Snapper-1.2.0-checksums.txt", "browser_download_url": "https://example.invalid/sum", "size": 96, "state": "uploaded" },
          { "name": "Snapper-1.2.0.zip", "browser_download_url": "https://example.invalid/1.2.0.zip", "size": 4194304, "state": "uploaded" },
          { "name": "Snapper-1.2.0.dmg", "browser_download_url": "https://example.invalid/1.2.0.dmg", "size": 6291456, "state": "uploaded" },
          { "name": "Snapper-1.2.0.pkg", "browser_download_url": "https://example.invalid/1.2.0.pkg", "size": 5242880, "state": "uploaded" }
        ]
      },
      {
        "tag_name": "v1.3.0-beta.1",
        "name": "",
        "body": "",
        "html_url": "https://github.com/chrisz24/Snapper/releases/tag/v1.3.0-beta.1",
        "draft": false,
        "prerelease": true,
        "published_at": "2026-08-15T10:00:00Z",
        "assets": []
      },
      {
        "tag_name": "v2.0.0",
        "name": "Unreleased",
        "body": "Should never be offered.",
        "html_url": "https://github.com/chrisz24/Snapper/releases/tag/v2.0.0",
        "draft": true,
        "prerelease": false,
        "published_at": null,
        "assets": []
      },
      {
        "tag_name": "nightly",
        "name": "Rolling",
        "body": "Not a version.",
        "html_url": "https://github.com/chrisz24/Snapper/releases/tag/nightly",
        "draft": false,
        "prerelease": false,
        "published_at": "2026-08-22T10:00:00Z",
        "assets": []
      }
    ]
    """

    private static func version(_ raw: String) -> AppVersion {
        guard let v = AppVersion(raw) else {
            fatalError("test fixture has an unparseable version: \(raw)")
        }
        return v
    }

    static func run() {
        Harness.suite("AppVersion") {
            Harness.test("parses a plain three-part version") {
                let v = version("1.2.3")
                Harness.expectEqual(v.components, [1, 2, 3])
                Harness.expectEqual(v.prerelease, "")
                Harness.expectEqual(v.displayString, "1.2.3")
            }

            Harness.test("tolerates the v prefix GitHub tags use") {
                Harness.expectEqual(version("v0.1.0"), version("0.1.0"))
            }

            Harness.test("orders by number, not by string") {
                // The whole reason this type exists: "0.10.0" < "0.9.9" as strings.
                Harness.expect(version("0.9.9") < version("0.10.0"))
                Harness.expect(version("1.0.0") < version("1.0.10"))
                Harness.expect(version("2.0.0") > version("1.99.99"))
            }

            Harness.test("pads missing components") {
                Harness.expectEqual(version("1.2"), version("1.2.0"))
                Harness.expect(version("1.2") < version("1.2.1"))
            }

            Harness.test("equal versions hash alike even when written differently") {
                Harness.expectEqual(version("1.2").hashValue, version("1.2.0").hashValue)
            }

            Harness.test("a pre-release ranks below its own release") {
                Harness.expect(version("1.3.0-beta.1") < version("1.3.0"))
                Harness.expect(version("1.3.0-beta.1") > version("1.2.9"))
            }

            Harness.test("orders pre-release identifiers the way semver says") {
                Harness.expect(version("1.0.0-alpha") < version("1.0.0-alpha.1"))
                Harness.expect(version("1.0.0-alpha.1") < version("1.0.0-alpha.beta"))
                Harness.expect(version("1.0.0-beta.2") < version("1.0.0-beta.11"))
                Harness.expect(version("1.0.0-rc.1") < version("1.0.0"))
            }

            Harness.test("build metadata does not affect precedence") {
                Harness.expectEqual(version("1.2.3+build9"), version("1.2.3+build10"))
                Harness.expectEqual(version("1.2.3+build9").displayString, "1.2.3")
            }

            Harness.test("flags a pre-release from its tag alone") {
                Harness.expect(version("1.0.0-rc.1").isPrerelease)
                Harness.expect(!version("1.0.0").isPrerelease)
            }

            Harness.test("rejects what is not a version") {
                for raw in ["", "v", "nightly", "1.2.x", "latest", "1..2", "-1.0.0", "1.2 .3"] {
                    Harness.expect(AppVersion(raw) == nil, "accepted \(raw)")
                }
            }
        }

        Harness.suite("Release feed") {
            let releases = (try? GitHubRelease.decodeFeed(Data(feed.utf8))) ?? []

            Harness.test("decodes every usable release and drops the rest") {
                // Five entries in, three out: the draft and the "nightly" tag are unusable.
                Harness.expectEqual(releases.count, 3)
                Harness.expect(!releases.contains { $0.tag == "v2.0.0" }, "kept a draft")
                Harness.expect(!releases.contains { $0.tag == "nightly" }, "kept an unparseable tag")
            }

            Harness.test("picks the highest version, not the most recently published") {
                let newest = UpdateResolver.newest(in: releases, includePrereleases: false)
                Harness.expectEqual(newest?.tag, "v1.2.0")
            }

            Harness.test("includes pre-releases only when asked") {
                Harness.expectEqual(UpdateResolver.newest(in: releases, includePrereleases: true)?.tag,
                                    "v1.3.0-beta.1")
            }

            Harness.test("prefers the installer over a dmg or zip, and never offers a checksum") {
                let latest = releases.first { $0.tag == "v1.2.0" }
                Harness.expectEqual(latest?.asset?.name, "Snapper-1.2.0.pkg")
            }

            Harness.test("still resolves a release that predates the installer") {
                // v0.9.0 in the fixture has only a .dmg, the way releases cut before the switch do.
                let older = releases.first { $0.tag == "v0.9.0" }
                Harness.expectEqual(older?.asset?.name, "Snapper-0.9.0.dmg")
            }

            Harness.test("falls back to the release page when nothing is attached") {
                let beta = releases.first { $0.tag == "v1.3.0-beta.1" }
                Harness.expect(beta?.asset == nil)
                Harness.expectEqual(beta?.downloadURL.absoluteString,
                                    "https://github.com/chrisz24/Snapper/releases/tag/v1.3.0-beta.1")
            }

            Harness.test("an empty release name falls back to the tag") {
                Harness.expectEqual(releases.first { $0.tag == "v1.3.0-beta.1" }?.title, "v1.3.0-beta.1")
            }

            Harness.test("a tagged pre-release counts as one even if the flag says otherwise") {
                // GitHub's checkbox is easy to forget; the tag is the more reliable signal.
                let json = """
                [{"tag_name":"v1.4.0-rc.1","name":"rc","body":"","html_url":"https://example.invalid/r",
                  "draft":false,"prerelease":false,"published_at":null,"assets":[]}]
                """
                let decoded = (try? GitHubRelease.decodeFeed(Data(json.utf8))) ?? []
                Harness.expectEqual(decoded.count, 1)
                Harness.expect(decoded.first?.isPrerelease == true)
            }

            Harness.test("a body that is only whitespace counts as no notes") {
                let json = """
                [{"tag_name":"v1.0.0","name":"n","body":"   \\n  ","html_url":"https://example.invalid/r",
                  "draft":false,"prerelease":false,"published_at":null,"assets":[]}]
                """
                let decoded = (try? GitHubRelease.decodeFeed(Data(json.utf8))) ?? []
                Harness.expect(decoded.first?.notes.isEmpty == true)
            }

            Harness.test("reports malformed JSON rather than returning nothing") {
                do {
                    _ = try GitHubRelease.decodeFeed(Data("{\"message\":\"Not Found\"}".utf8))
                    Harness.expect(false, "should have thrown")
                } catch {
                    Harness.expectEqual(error as? UpdateError, .malformedFeed)
                }
            }

            Harness.test("an empty feed decodes to an empty list") {
                Harness.expectEqual((try? GitHubRelease.decodeFeed(Data("[]".utf8)))?.count, 0)
            }
        }

        Harness.suite("Offering an update") {
            let releases = (try? GitHubRelease.decodeFeed(Data(feed.utf8))) ?? []
            guard let latest = releases.first(where: { $0.tag == "v1.2.0" }) else {
                Harness.test("fixture has v1.2.0") { Harness.expect(false) }
                return
            }

            Harness.test("offers a newer version") {
                Harness.expect(UpdateResolver.isWorthOffering(latest, current: version("1.1.0")))
            }

            Harness.test("does not offer the version already installed") {
                Harness.expect(!UpdateResolver.isWorthOffering(latest, current: version("1.2.0")))
            }

            Harness.test("does not offer an older version") {
                Harness.expect(!UpdateResolver.isWorthOffering(latest, current: version("1.5.0")))
            }

            Harness.test("treats a build-metadata difference as the same version") {
                Harness.expect(!UpdateResolver.isWorthOffering(latest, current: version("1.2.0+202608231200")))
            }

            Harness.test("a skipped version stops being offered") {
                Harness.expect(!UpdateResolver.isWorthOffering(latest, current: version("1.1.0"), skipping: "1.2.0"))
            }

            Harness.test("skipping one version does not skip the next") {
                Harness.expect(UpdateResolver.isWorthOffering(latest, current: version("1.1.0"), skipping: "1.1.5"))
            }

            Harness.test("a nonsense skip value is ignored, not obeyed") {
                Harness.expect(UpdateResolver.isWorthOffering(latest, current: version("1.1.0"), skipping: "garbage"))
            }
        }

        Harness.suite("Update defaults") {
            Harness.test("checks are on, pre-releases are not, nothing skipped") {
                let suite = "snapper.tests.updates.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
                MainActor.assumeIsolated {
                    let settings = SettingsStore(defaults: defaults)
                    Harness.expect(settings.automaticUpdateChecks)
                    Harness.expect(!settings.includePrereleaseUpdates)
                    Harness.expectEqual(settings.skippedUpdateVersion, "")
                    Harness.expectEqual(settings.lastUpdateCheck, 0)
                }
            }

            Harness.test("a fresh install is due for a check straight away") {
                let suite = "snapper.tests.updates.due.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
                MainActor.assumeIsolated {
                    let checker = UpdateChecker(settings: SettingsStore(defaults: defaults))
                    Harness.expect(checker.isCheckDue)
                    Harness.expect(checker.lastCheckedAt == nil)
                }
            }

            Harness.test("a check just made is not due again") {
                let suite = "snapper.tests.updates.notdue.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
                MainActor.assumeIsolated {
                    let settings = SettingsStore(defaults: defaults)
                    settings.lastUpdateCheck = Date().timeIntervalSince1970
                    Harness.expect(!UpdateChecker(settings: settings).isCheckDue)
                }
            }

            Harness.test("a check from over a day ago is due again") {
                let suite = "snapper.tests.updates.stale.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
                MainActor.assumeIsolated {
                    let settings = SettingsStore(defaults: defaults)
                    settings.lastUpdateCheck = Date().timeIntervalSince1970 - (UpdateChecker.checkInterval + 60)
                    Harness.expect(UpdateChecker(settings: settings).isCheckDue)
                }
            }
        }

        Harness.suite("Installer verification") {
            // Real `pkgutil --check-signature` output. The team has to come from the leaf, not from
            // anywhere else in the chain — Apple's intermediate and root carry no team, and a
            // looser match would read the wrong line.
            let signed = """
            Package "Snapper-0.1.1.pkg":
               Status: signed by a developer certificate issued by Apple for distribution
               Signed with a trusted timestamp on: 2026-08-24 20:42:37 +0000
               Certificate Chain:
                1. Developer ID Installer: Christos Zikopoulos (6N9UZU4A8S)
                   Expires: 2031-08-25 19:53:33 +0000
                   ------------------------------------------------------------------------
                2. Developer ID Certification Authority
                   Expires: 2031-09-17 00:00:00 +0000
                   ------------------------------------------------------------------------
                3. Apple Root CA
                   Expires: 2035-02-09 21:40:36 +0000
            """

            Harness.test("reads the team from the leaf certificate") {
                Harness.expectEqual(UpdateInstaller.teamIdentifier(inPkgutilOutput: signed), "6N9UZU4A8S")
            }

            Harness.test("an unsigned package yields no team") {
                let unsigned = """
                Package "Snapper-0.1.1.pkg":
                   Status: no signature
                """
                Harness.expect(UpdateInstaller.teamIdentifier(inPkgutilOutput: unsigned) == nil)
            }

            Harness.test("an Application certificate is not accepted as an Installer one") {
                // Signing a package with the wrong certificate type must not pass the team check.
                let wrongKind = """
                Package "x.pkg":
                   Certificate Chain:
                    1. Developer ID Application: Christos Zikopoulos (6N9UZU4A8S)
                """
                Harness.expect(UpdateInstaller.teamIdentifier(inPkgutilOutput: wrongKind) == nil)
            }

            Harness.test("a certificate with no team in it yields nothing") {
                let noTeam = """
                Package "x.pkg":
                   Certificate Chain:
                    1. Developer ID Installer: Someone
                """
                Harness.expect(UpdateInstaller.teamIdentifier(inPkgutilOutput: noTeam) == nil)
            }

            Harness.test("empty output yields nothing rather than crashing") {
                Harness.expect(UpdateInstaller.teamIdentifier(inPkgutilOutput: "") == nil)
            }

            Harness.test("a release with no pkg is not installable in place") {
                let json = """
                [{"tag_name":"v9.0.0","name":"n","body":"","html_url":"https://example.invalid/r",
                  "draft":false,"prerelease":false,"published_at":null,
                  "assets":[{"name":"Snapper-9.0.0.zip","browser_download_url":"https://example.invalid/z","size":10,"state":"uploaded"}]}]
                """
                let decoded = (try? GitHubRelease.decodeFeed(Data(json.utf8))) ?? []
                let installable = decoded.first?.asset?.name.lowercased().hasSuffix(".pkg") ?? false
                Harness.expect(!installable, "a zip must fall back to the browser, not be installed")
            }
        }

        Harness.suite("Update endpoint") {
            Harness.test("points at the configured repository") {
                Harness.expectEqual(AppInfo.repositoryURL.absoluteString,
                                    "https://github.com/chrisz24/Snapper")
                Harness.expectEqual(AppInfo.releasesPageURL.absoluteString,
                                    "https://github.com/chrisz24/Snapper/releases")
            }

            Harness.test("asks for the whole release list, not GitHub's idea of latest") {
                let url = AppInfo.releasesAPIURL.absoluteString
                Harness.expect(url.hasPrefix("https://api.github.com/repos/chrisz24/Snapper/releases"), url)
                Harness.expect(!url.contains("/latest"), url)
            }
        }
    }
}
