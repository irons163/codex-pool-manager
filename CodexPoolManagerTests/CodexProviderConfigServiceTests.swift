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
