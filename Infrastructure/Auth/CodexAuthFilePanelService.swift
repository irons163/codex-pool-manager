import Foundation
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct CodexAuthFilePanelService {
    func pickAuthFileURL() -> URL? {
#if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "選擇"
        panel.message = "請選擇 ~/.codex/auth.json"

        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
        panel.directoryURL = codexDirectory
        panel.nameFieldStringValue = "auth.json"

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
#else
        return nil
#endif
    }
}
