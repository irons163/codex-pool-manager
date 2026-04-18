import Foundation
import Testing
@testable import CodexPoolManager

struct AppUpdateServiceTests {
    @Test
    func versionComparisonTreatsRemoteAsNewer() {
        #expect(AppUpdateVersioning.isRemoteNewer(current: "1.7.2", remote: "1.7.5"))
        #expect(AppUpdateVersioning.isRemoteNewer(current: "v1.7.2", remote: "v1.8.0"))
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
}
