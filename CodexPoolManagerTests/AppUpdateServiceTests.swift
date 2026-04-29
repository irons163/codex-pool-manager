import Foundation
import Testing
@testable import CodexPoolManager

@MainActor
struct AppUpdateServiceTests {
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
