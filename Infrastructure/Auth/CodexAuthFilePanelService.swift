import Foundation
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct CodexAuthFilePanelService {
    private let picker: () -> URL?

    init(picker: @escaping () -> URL?) {
        self.picker = picker
    }

    @MainActor
    init() {
        self.picker = { Self.defaultPicker() }
    }

    func pickAuthFileURL() -> URL? {
        picker()
    }

    @MainActor
    private static func defaultPicker() -> URL? {
#if canImport(AppKit)
        let panel = configuredOpenPanel()

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
#else
        return nil
#endif
    }

    #if canImport(AppKit)
    @MainActor
    static func configuredOpenPanel(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = L10n.text("common.choose")
        panel.message = L10n.text("auth.file_panel.message_select_auth_json")
        panel.directoryURL = homeDirectory.appending(path: ".codex")
        panel.nameFieldStringValue = "auth.json"
        return panel
    }
    #endif
}
