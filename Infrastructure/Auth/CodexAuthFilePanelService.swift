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
        panel.prompt = L10n.text("common.choose")
        panel.message = L10n.text("auth.file_panel.message_select_auth_json")

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
