import Foundation

struct CodexAuthFileAccessService {
    private static let fallbackAuthRelativePath = ".codex/auth.json"

    enum AccessError: LocalizedError {
        case missingAuthFile

        var errorDescription: String? {
            switch self {
            case .missingAuthFile:
                return "找不到 auth.json，請先按「選擇 auth.json」授權"
            }
        }
    }

    let bookmarkKey: String

    init(bookmarkKey: String) {
        self.bookmarkKey = bookmarkKey
    }

    func saveBookmark(for url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    func loadAuthorizedURLFromBookmark() throws -> (url: URL, wasStale: Bool) {
        let bookmark = try bookmarkData()
        return try resolveURL(from: bookmark)
    }

    func hasSavedBookmark() -> Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    func loadAccounts(from url: URL) throws -> [LocalCodexOAuthAccount] {
        let data = try withSecurityScope(url: url) {
            try Data(contentsOf: url)
        }
        return LocalCodexAccountDiscovery.parseAccounts(from: data, source: url.path)
    }

    func resolveAuthFileURLForSwitch(sessionAuthorizedURL: URL?) throws -> URL {
        if let sessionAuthorizedURL {
            return sessionAuthorizedURL
        }

        if let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) {
            return try resolveURL(from: bookmark).url
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: Self.fallbackAuthRelativePath)
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }

        throw AccessError.missingAuthFile
    }

    func withSecurityScope<T>(url: URL, _ body: () throws -> T) throws -> T {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }

    private func bookmarkData() throws -> Data {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw AccessError.missingAuthFile
        }
        return bookmark
    }

    private func resolveURL(from bookmark: Data) throws -> (url: URL, wasStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }
}
