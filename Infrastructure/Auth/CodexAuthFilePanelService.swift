import Foundation
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct CodexAuthFilePanelService {
    private let picker: () -> URL?

#if DEBUG
    @MainActor
    static var defaultPickerOverride: (() -> URL?)?

    @MainActor
    static var runModalOverride: ((NSOpenPanel) -> NSApplication.ModalResponse)?
#endif

    init(picker: @escaping () -> URL?) {
        self.picker = picker
    }

    @MainActor
    init() {
        self.picker = {
#if DEBUG
            if let override = Self.defaultPickerOverride {
                return override()
            }
#endif
            return Self.defaultPicker()
        }
    }

    func pickAuthFileURL() -> URL? {
        picker()
    }

    @MainActor
    private static func defaultPicker() -> URL? {
#if canImport(AppKit)
        let panel = configuredOpenPanel()
        return pickURLFromPanel(panel)
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

    @MainActor
    static func pickURLFromPanel(
        _ panel: NSOpenPanel,
        runModal: ((NSOpenPanel) -> NSApplication.ModalResponse)? = nil
    ) -> URL? {
        let modalResult: NSApplication.ModalResponse
        if let runModal {
            modalResult = runModal(panel)
        } else {
#if DEBUG
            if let override = Self.runModalOverride {
                modalResult = override(panel)
            } else {
                modalResult = panel.runModal()
            }
#else
            modalResult = panel.runModal()
#endif
        }

        guard modalResult == .OK else {
            return nil
        }
        return panel.url
    }
    #endif
}
