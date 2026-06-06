import Foundation
import Testing
@testable import CodexPoolManager

struct CodexProviderConfigServiceTests {
    @Test
    func providerConfigRendersMirrorTable() throws {
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            requiresOpenAIAuth: true
        )

        let rendered = config.renderTOMLBlock()

        #expect(rendered.contains("[model_providers.mirror]"))
        #expect(rendered.contains("name = \"mirror\""))
        #expect(rendered.contains("base_url = \"https://ai.liaryai.com/api/codex\""))
        #expect(rendered.contains("wire_api = \"responses\""))
        #expect(rendered.contains("requires_openai_auth = true"))
    }

    @Test
    func configMergeInsertsModelProviderIntoEmptyConfig() throws {
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            requiresOpenAIAuth: true
        )

        let merged = CodexProviderConfigMerger.merge(existing: "", provider: config)

        #expect(merged.hasPrefix("model_provider = \"mirror\""))
        #expect(merged.contains("[model_providers.mirror]"))
    }

    @Test
    func configMergeReplacesTopLevelModelProviderAndSameProviderTableOnly() throws {
        let existing = """
        model = "gpt-5.1-codex"
        model_provider = "openai"

        [model_providers.other]
        name = "other"
        base_url = "https://other.example.com/v1"
        wire_api = "responses"
        requires_openai_auth = false

        [model_providers.mirror]
        name = "old"
        base_url = "https://old.example.com/v1"
        wire_api = "chat"
        requires_openai_auth = false
        """
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            requiresOpenAIAuth: true
        )

        let merged = CodexProviderConfigMerger.merge(existing: existing, provider: config)

        #expect(merged.contains("model = \"gpt-5.1-codex\""))
        #expect(merged.contains("model_provider = \"mirror\""))
        #expect(merged.contains("[model_providers.other]"))
        #expect(merged.contains("base_url = \"https://other.example.com/v1\""))
        #expect(!merged.contains("https://old.example.com/v1"))
        #expect(merged.contains("base_url = \"https://ai.liaryai.com/api/codex\""))
    }

    @Test
    func enhancedConfigMergeWritesProviderScopedBearerToken() throws {
        let existing = """
        model = "gpt-5.1-codex"
        model_provider = "openai"

        [model_providers.other]
        name = "other"
        experimental_bearer_token = "sk-other"
        """
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            requiresOpenAIAuth: true
        )

        let merged = CodexProviderConfigMerger.mergePreservingOfficialAuth(
            existing: existing,
            provider: config,
            apiKey: "sk-relay"
        )

        #expect(merged.contains("model_provider = \"mirror\""))
        #expect(merged.contains("[model_providers.mirror]"))
        #expect(merged.contains("experimental_bearer_token = \"sk-relay\""))
        #expect(merged.contains("[model_providers.other]"))
        #expect(merged.contains("experimental_bearer_token = \"sk-other\""))
    }

    @Test
    func configResetRemovesOnlyTopLevelModelProvider() {
        let existing = """
        model = "gpt-5.1-codex"
        model_provider = "mirror"

        [model_providers.mirror]
        name = "mirror"
        base_url = "https://ai.liaryai.com/api/codex"
        wire_api = "responses"
        requires_openai_auth = true

        [profiles.testing]
        model_provider = "keep-profile-provider"
        """

        let reset = CodexProviderConfigMerger.resetModelProvider(existing: existing)

        #expect(reset.contains("model = \"gpt-5.1-codex\""))
        #expect(!reset.contains("\nmodel_provider = \"mirror\""))
        #expect(reset.hasPrefix("model = \"gpt-5.1-codex\""))
        #expect(reset.contains("[model_providers.mirror]"))
        #expect(reset.contains("base_url = \"https://ai.liaryai.com/api/codex\""))
        #expect(reset.contains("model_provider = \"keep-profile-provider\""))
    }

    @Test
    func configResetRemovesOnlyActiveEnhancedBearerToken() {
        let existing = """
        model = "gpt-5.1-codex"
        model_provider = "mirror"

        [model_providers.mirror]
        name = "mirror"
        base_url = "https://ai.liaryai.com/api/codex"
        experimental_bearer_token = "sk-relay"

        [model_providers.other]
        name = "other"
        experimental_bearer_token = "sk-other"
        """

        let reset = CodexProviderConfigMerger.resetModelProvider(existing: existing)

        #expect(!reset.contains("\nmodel_provider = \"mirror\""))
        #expect(!reset.contains("experimental_bearer_token = \"sk-relay\""))
        #expect(reset.contains("experimental_bearer_token = \"sk-other\""))
    }

    @Test
    func configServiceResetWritesDefaultProviderConfigToDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-provider-reset-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        model = "gpt-5.1-codex"
        model_provider = "mirror"

        [model_providers.mirror]
        name = "mirror"
        base_url = "https://ai.liaryai.com/api/codex"
        wire_api = "responses"
        requires_openai_auth = true
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let service = CodexProviderConfigService(configURLProvider: { configURL })
        try service.resetToDefaultModelProvider()

        let reset = try String(contentsOf: configURL, encoding: .utf8)
        #expect(!reset.contains("\nmodel_provider = \"mirror\""))
        #expect(reset.contains("model = \"gpt-5.1-codex\""))
        #expect(reset.contains("[model_providers.mirror]"))
    }

    @Test
    func providerConfigRejectsInvalidProviderID() {
        #expect(throws: CodexProviderConfigError.invalidProviderID) {
            _ = try CodexProviderConfig(
                providerID: "mirror-prod",
                name: "mirror-prod",
                baseURL: "https://ai.liaryai.com/api/codex",
                wireAPI: "responses",
                requiresOpenAIAuth: true
            )
        }
    }
}

struct CodexAPIKeyLoginServiceTests {
    @Test
    func loginAddsHomebrewNodePathsToProcessEnvironment() async throws {
        var receivedEnvironment: [String: String]?
        let service = CodexAPIKeyLoginService(
            executableURLProvider: { URL(fileURLWithPath: "/tmp/codex") },
            processRunner: { _, _, _, environment in
                receivedEnvironment = environment
                return (0, "")
            }
        )

        try await service.login(apiKey: "sk-test")

        let path = try #require(receivedEnvironment?["PATH"])
        let entries = path.split(separator: ":").map(String.init)
        #expect(entries.contains("/opt/homebrew/bin"))
        #expect(entries.contains("/usr/local/bin"))
        #expect(entries.contains("/usr/bin"))
    }
}
