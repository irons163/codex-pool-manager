import Foundation
import Testing
@testable import CodexPoolManager

private let appUpdateLanguageOverrideMutationLock = NSLock()

private func withAppUpdateLanguageOverride(_ languageCode: String, _ body: () throws -> Void) rethrows {
    appUpdateLanguageOverrideMutationLock.lock()
    defer { appUpdateLanguageOverrideMutationLock.unlock() }

    let defaults = UserDefaults.standard
    let key = L10n.languageOverrideKey
    let previous = defaults.object(forKey: key)
    defer {
        if let previous {
            defaults.set(previous, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    defaults.set(languageCode, forKey: key)
    try body()
}

@MainActor
struct AppUpdateServiceTests {
    @Test
    func appUpdateErrorDescriptionsAreNonEmptyAndSpecific() {
        #expect(AppUpdateError.invalidResponse.errorDescription == "Invalid update response.")
        #expect(AppUpdateError.decodingFailed.errorDescription == "Failed to decode update metadata.")
        #expect(AppUpdateError.noPrereleaseAvailable.errorDescription == "No prerelease update is available.")
    }

    @Test
    func normalizedVersionTrimsPrefixAndWhitespace() {
        #expect(AppUpdateVersioning.normalizedVersion(from: " v1.7.5 ") == "1.7.5")
        #expect(AppUpdateVersioning.normalizedVersion(from: "V2.0.1") == "2.0.1")
        #expect(AppUpdateVersioning.normalizedVersion(from: "  ") == "0")
    }

    @Test
    func versionComparisonTreatsRemoteAsNewer() {
        #expect(AppUpdateVersioning.isRemoteNewer(current: "1.7.2", remote: "1.7.5"))
        #expect(AppUpdateVersioning.isRemoteNewer(current: "v1.7.2", remote: "v1.8.0"))
        #expect(AppUpdateVersioning.isRemoteNewer(current: "1.7", remote: "1.7.1"))
        #expect(AppUpdateVersioning.isRemoteNewer(current: "1.7.9", remote: "1.8.0-beta.1"))
        #expect(!AppUpdateVersioning.isRemoteNewer(current: "1.7.5", remote: "1.7.5"))
        #expect(!AppUpdateVersioning.isRemoteNewer(current: "1.8.0", remote: "1.7.9"))
    }

    @Test
    func automaticUpdateCheckPolicyRunsInitially() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(AppUpdateAutoCheckPolicy.shouldRun(lastCheckedAt: 0, now: now))
    }

    @Test
    func automaticUpdateCheckPolicyUsesThirtyMinuteInterval() {
        #expect(AppUpdateAutoCheckPolicy.intervalSeconds == 30 * 60)
    }

    @Test
    func automaticUpdateCheckPolicyWaitsForInterval() {
        let now = Date(timeIntervalSince1970: 10_000)
        let lastCheckedAt = now.timeIntervalSince1970 - AppUpdateAutoCheckPolicy.intervalSeconds + 1

        #expect(!AppUpdateAutoCheckPolicy.shouldRun(lastCheckedAt: lastCheckedAt, now: now))
    }

    @Test
    func automaticUpdateCheckPolicyRunsAfterInterval() {
        let now = Date(timeIntervalSince1970: 10_000)
        let lastCheckedAt = now.timeIntervalSince1970 - AppUpdateAutoCheckPolicy.intervalSeconds

        #expect(AppUpdateAutoCheckPolicy.shouldRun(lastCheckedAt: lastCheckedAt, now: now))
    }

    @Test
    func whatsNewPolicyUsesVersionAndBuildToDecideVisibility() {
        let currentID = WhatsNewPromptPolicy.versionID(version: "v1.0.14-rc.18", build: "118")

        #expect(currentID == "1.0.14-rc.18+118")
        #expect(WhatsNewPromptPolicy.shouldShow(currentVersionID: currentID, lastSeenVersionID: ""))
        #expect(!WhatsNewPromptPolicy.shouldShow(currentVersionID: currentID, lastSeenVersionID: currentID))
        #expect(WhatsNewPromptPolicy.shouldShow(currentVersionID: currentID, lastSeenVersionID: "1.0.14-rc.18+117"))
        #expect(WhatsNewPromptPolicy.shouldShow(currentVersionID: currentID, lastSeenVersionID: "1.0.14-rc.17+118"))
    }

    @Test
    func whatsNewAnnouncementUsesApprovedResetCreditCopy() {
        withAppUpdateLanguageOverride("zh-Hant") {
            let announcement = WhatsNewAnnouncement.current(version: "1.0.14-rc.18", build: "118")

            #expect(announcement.id == "1.0.14-rc.18+118")
            #expect(announcement.displayVersion == "1.0.14-rc.18")
            #expect(announcement.sections.contains { section in
                section.bodyLines.contains { line in
                    line.contains("可重置 2 次 · 7/30, 8/1")
                }
            })
        }
    }

    @Test
    func preferredInstallerSelectsArchitectureSpecificAsset() {
        let release = AppUpdateRelease(
            tagName: "v1.7.5",
            name: "v1.7.5",
            htmlURL: URL(string: "https://example.com/release")!,
            publishedAt: nil,
            assets: [
                AppUpdateAsset(
                    name: "CodexPoolManager-1.7.5-apple-silicon.dmg",
                    downloadURL: URL(string: "https://example.com/apple.dmg")!
                ),
                AppUpdateAsset(
                    name: "CodexPoolManager-1.7.5-intel.dmg",
                    downloadURL: URL(string: "https://example.com/intel.dmg")!
                )
            ]
        )

        #expect(release.preferredInstallerURL(for: .appleSilicon)?.absoluteString == "https://example.com/apple.dmg")
        #expect(release.preferredInstallerURL(for: .intel)?.absoluteString == "https://example.com/intel.dmg")
    }

    @Test
    func preferredInstallerFallsBackToFirstDMGWhenArchitectureSpecificAssetMissing() {
        let release = AppUpdateRelease(
            tagName: "v1.7.5",
            name: "v1.7.5",
            htmlURL: URL(string: "https://example.com/release")!,
            publishedAt: nil,
            assets: [
                AppUpdateAsset(
                    name: "CodexPoolManager-1.7.5-universal.dmg",
                    downloadURL: URL(string: "https://example.com/universal.dmg")!
                )
            ]
        )

        #expect(release.preferredInstallerURL(for: .appleSilicon)?.absoluteString == "https://example.com/universal.dmg")
        #expect(release.preferredInstallerURL(for: .intel)?.absoluteString == "https://example.com/universal.dmg")
        #expect(release.preferredInstallerURL(for: .unknown)?.absoluteString == "https://example.com/universal.dmg")
    }

    @Test
    func buildMatrixLinesNormalizesKnownDmgNames() {
        let release = AppUpdateRelease(
            tagName: "v1.7.5",
            name: "v1.7.5",
            htmlURL: URL(string: "https://example.com/release")!,
            publishedAt: nil,
            assets: [
                AppUpdateAsset(
                    name: "CodexPoolManager-1.7.5-apple-silicon.dmg",
                    downloadURL: URL(string: "https://example.com/apple.dmg")!
                ),
                AppUpdateAsset(
                    name: "CodexPoolManager-1.7.5-intel.dmg",
                    downloadURL: URL(string: "https://example.com/intel.dmg")!
                )
            ]
        )

        #expect(release.buildMatrixLines == [
            "macOS Apple Silicon (arm64)",
            "macOS Intel (x86_64)"
        ])
    }

    @Test
    func buildMatrixLinesIgnoresNonDMGAssetsAndKeepsUnknownDMGName() {
        let release = AppUpdateRelease(
            tagName: "v1.7.5",
            name: "v1.7.5",
            htmlURL: URL(string: "https://example.com/release")!,
            publishedAt: nil,
            assets: [
                AppUpdateAsset(
                    name: "CodexPoolManager-1.7.5.zip",
                    downloadURL: URL(string: "https://example.com/release.zip")!
                ),
                AppUpdateAsset(
                    name: "CodexPoolManager-1.7.5.dmg",
                    downloadURL: URL(string: "https://example.com/release.dmg")!
                )
            ]
        )

        #expect(release.buildMatrixLines == ["CodexPoolManager-1.7.5.dmg"])
    }

    @Test
    func fetchLatestReleaseBuildsExpectedRequestAndParsesPayload() async throws {
        let endpoint = URL(string: "https://example.com/releases/latest")!
        let payload = """
        {
          "tag_name": "v1.8.0",
          "name": "Release 1.8.0",
          "html_url": "https://example.com/releases/v1.8.0",
          "published_at": "2026-04-18T08:30:45.123Z",
          "assets": [
            {
              "name": "CodexPoolManager-1.8.0-apple-silicon.dmg",
              "browser_download_url": "https://example.com/download/apple.dmg"
            },
            {
              "name": "CodexPoolManager-1.8.0-intel.dmg",
              "browser_download_url": "https://example.com/download/intel.dmg"
            }
          ]
        }
        """

        let observedHeaders = LockedValue<[String: String]>([:])
        let session = makeMockedURLSession(
            endpoint: endpoint,
            statusCode: 200,
            data: Data(payload.utf8),
            requestObserver: { request in
                observedHeaders.withLock { headers in
                    headers["method"] = request.httpMethod
                    headers["accept"] = request.value(forHTTPHeaderField: "Accept")
                    headers["userAgent"] = request.value(forHTTPHeaderField: "User-Agent")
                }
            }
        )
        let service = AppUpdateService(endpoint: endpoint, session: session)

        let release = try await service.fetchLatestRelease()

        #expect(release.tagName == "v1.8.0")
        #expect(release.displayTitle == "Release 1.8.0")
        #expect(release.normalizedVersion == "1.8.0")
        #expect(release.assets.count == 2)
        #expect(release.preferredInstallerURL(for: .appleSilicon)?.absoluteString == "https://example.com/download/apple.dmg")
        #expect(release.publishedAt != nil)

        let headers = observedHeaders.value
        #expect(headers["method"] == "GET")
        #expect(headers["accept"] == "application/vnd.github+json")
        #expect(headers["userAgent"] == "CodexPoolManager/1.0")
    }

    @Test
    func fetchLatestReleaseCanOptIntoPrereleaseChannel() async throws {
        let endpoint = URL(string: "https://example.com/prerelease-opt-in/releases/latest")!
        let prereleaseEndpoint = URL(string: "https://example.com/prerelease-opt-in/releases?per_page=20")!
        let payload = """
        [
          {
            "tag_name": "v1.10.0-beta.1",
            "name": "Beta 1.10.0",
            "html_url": "https://example.com/releases/v1.10.0-beta.1",
            "published_at": "2026-04-19T08:30:45Z",
            "draft": false,
            "prerelease": true,
            "assets": [
              {
                "name": "CodexPoolManager-1.10.0-beta.1-apple-silicon.dmg",
                "browser_download_url": "https://example.com/download/beta-apple.dmg"
              }
            ]
          },
          {
            "tag_name": "v1.9.0",
            "name": "Stable 1.9.0",
            "html_url": "https://example.com/releases/v1.9.0",
            "published_at": "2026-04-18T08:30:45Z",
            "draft": false,
            "prerelease": false,
            "assets": []
          }
        ]
        """
        let observedURL = LockedValue<String?>(nil)
        let session = makeMockedURLSession(
            endpoint: prereleaseEndpoint,
            statusCode: 200,
            data: Data(payload.utf8),
            requestObserver: { request in
                observedURL.withLock { value in
                    value = request.url?.absoluteString
                }
            }
        )
        let service = AppUpdateService(endpoint: endpoint, session: session)

        let release = try await service.fetchLatestRelease(includePrerelease: true)

        #expect(observedURL.value == prereleaseEndpoint.absoluteString)
        #expect(release.tagName == "v1.10.0-beta.1")
        #expect(release.normalizedVersion == "1.10.0-beta.1")
        #expect(release.preferredInstallerURL(for: .appleSilicon)?.absoluteString == "https://example.com/download/beta-apple.dmg")
    }

    @Test
    func fetchLatestReleaseUsesStableReleaseWhenPrereleaseChannelHasNoNewerBeta() async throws {
        let endpoint = URL(string: "https://example.com/prerelease-stable/releases/latest")!
        let prereleaseEndpoint = URL(string: "https://example.com/prerelease-stable/releases?per_page=20")!
        let payload = """
        [
          {
            "tag_name": "v1.9.0",
            "name": "Stable 1.9.0",
            "html_url": "https://example.com/releases/v1.9.0",
            "published_at": "2026-04-18T08:30:45Z",
            "draft": false,
            "prerelease": false,
            "assets": [
              {
                "name": "CodexPoolManager-1.9.0-apple-silicon.dmg",
                "browser_download_url": "https://example.com/download/stable-apple.dmg"
              }
            ]
          }
        ]
        """
        let session = makeMockedURLSession(
            endpoint: prereleaseEndpoint,
            statusCode: 200,
            data: Data(payload.utf8)
        )
        let service = AppUpdateService(endpoint: endpoint, session: session)

        let release = try await service.fetchLatestRelease(includePrerelease: true)

        #expect(release.tagName == "v1.9.0")
        #expect(release.normalizedVersion == "1.9.0")
        #expect(release.preferredInstallerURL(for: .appleSilicon)?.absoluteString == "https://example.com/download/stable-apple.dmg")
    }

    @Test
    func fetchLatestReleaseThrowsWhenPrereleaseChannelHasNoVisibleRelease() async {
        let endpoint = URL(string: "https://example.com/prerelease-empty/releases/latest")!
        let prereleaseEndpoint = URL(string: "https://example.com/prerelease-empty/releases?per_page=20")!
        let payload = """
        [
          {
            "tag_name": "v1.9.0",
            "name": "Draft stable",
            "html_url": "https://example.com/releases/v1.9.0",
            "draft": true,
            "prerelease": false,
            "assets": []
          },
          {
            "tag_name": "v1.10.0-beta.1",
            "name": "Draft beta",
            "html_url": "https://example.com/releases/v1.10.0-beta.1",
            "draft": true,
            "prerelease": true,
            "assets": []
          }
        ]
        """
        let session = makeMockedURLSession(
            endpoint: prereleaseEndpoint,
            statusCode: 200,
            data: Data(payload.utf8)
        )
        let service = AppUpdateService(endpoint: endpoint, session: session)

        await #expect(throws: AppUpdateError.noPrereleaseAvailable) {
            _ = try await service.fetchLatestRelease(includePrerelease: true)
        }
    }

    @Test
    func fetchLatestReleaseParsesISO8601WithoutFractionalSeconds() async throws {
        let endpoint = URL(string: "https://example.com/releases/latest-nofraction")!
        let payload = """
        {
          "tag_name": "v1.8.1",
          "name": "Release 1.8.1",
          "html_url": "https://example.com/releases/v1.8.1",
          "published_at": "2026-04-18T08:30:45Z",
          "assets": []
        }
        """
        let session = makeMockedURLSession(
            endpoint: endpoint,
            statusCode: 200,
            data: Data(payload.utf8)
        )
        let service = AppUpdateService(endpoint: endpoint, session: session)

        let release = try await service.fetchLatestRelease()

        #expect(release.publishedAt != nil)
    }

    @Test
    func fetchLatestReleaseUsesLocalizedNotesAssetForRequestedLanguage() async throws {
        let endpoint = URL(string: "https://example.com/releases/latest-localized")!
        let zhNotesURL = URL(string: "https://example.com/download/release-notes.zh-Hant.md")!
        let payload = """
        {
          "tag_name": "v1.8.2",
          "name": "Release 1.8.2",
          "html_url": "https://example.com/releases/v1.8.2",
          "published_at": "2026-04-18T08:30:45Z",
          "body": "Default English body from GitHub release.",
          "assets": [
            {
              "name": "release-notes.en.md",
              "browser_download_url": "https://example.com/download/release-notes.en.md"
            },
            {
              "name": "release-notes.zh-Hant.md",
              "browser_download_url": "https://example.com/download/release-notes.zh-Hant.md"
            }
          ]
        }
        """
        let session = makeMockedURLSession(
            endpoint: endpoint,
            statusCode: 200,
            data: Data(payload.utf8)
        )
        MockUsageURLProtocol.setMock(
            for: zhNotesURL.absoluteString,
            statusCode: 200,
            data: Data("繁體中文更新說明".utf8),
            requestObserver: nil
        )

        let service = AppUpdateService(endpoint: endpoint, session: session)
        let release = try await service.fetchLatestRelease(languageOverrideCode: "zh-Hant")

        #expect(release.releaseNotesText == "繁體中文更新說明")
        #expect(release.notesLanguageCode == "zh-hant")
    }

    @Test
    func fetchLatestReleaseFallsBackToEnglishNotesAssetWhenRequestedLanguageMissing() async throws {
        let endpoint = URL(string: "https://example.com/releases/latest-fallback-en")!
        let enNotesURL = URL(string: "https://example.com/download/release-notes.en.md")!
        let payload = """
        {
          "tag_name": "v1.8.3",
          "name": "Release 1.8.3",
          "html_url": "https://example.com/releases/v1.8.3",
          "published_at": "2026-04-18T08:30:45Z",
          "body": "Default English body from GitHub release.",
          "assets": [
            {
              "name": "release-notes.en.md",
              "browser_download_url": "https://example.com/download/release-notes.en.md"
            }
          ]
        }
        """
        let session = makeMockedURLSession(
            endpoint: endpoint,
            statusCode: 200,
            data: Data(payload.utf8)
        )
        MockUsageURLProtocol.setMock(
            for: enNotesURL.absoluteString,
            statusCode: 200,
            data: Data("English notes from asset".utf8),
            requestObserver: nil
        )

        let service = AppUpdateService(endpoint: endpoint, session: session)
        let release = try await service.fetchLatestRelease(languageOverrideCode: "ja")

        #expect(release.releaseNotesText == "English notes from asset")
        #expect(release.notesLanguageCode == "en")
    }

    @Test
    func fetchLatestReleaseThrowsInvalidResponseOnNonSuccessStatus() async {
        let endpoint = URL(string: "https://example.com/releases/failure")!
        let session = makeMockedURLSession(
            endpoint: endpoint,
            statusCode: 503,
            data: Data("{}".utf8)
        )
        let service = AppUpdateService(endpoint: endpoint, session: session)

        await #expect(throws: AppUpdateError.invalidResponse) {
            _ = try await service.fetchLatestRelease()
        }
    }

    @Test
    func fetchLatestReleaseThrowsDecodingFailedOnMalformedPayload() async {
        let endpoint = URL(string: "https://example.com/releases/malformed")!
        let session = makeMockedURLSession(
            endpoint: endpoint,
            statusCode: 200,
            data: Data("{\"unexpected\":\"shape\"}".utf8)
        )
        let service = AppUpdateService(endpoint: endpoint, session: session)

        await #expect(throws: AppUpdateError.decodingFailed) {
            _ = try await service.fetchLatestRelease()
        }
    }
}
