import Foundation
import Testing
@testable import CodexPoolManager

struct CodexProviderConfigServiceTests {
    @Test
    func providerConfigErrorsExposeLocalizedDescriptions() {
        #expect(CodexProviderConfigError.invalidProviderID.errorDescription == L10n.text("relay.error.invalid_provider_id"))
        #expect(CodexProviderConfigError.invalidBaseURL.errorDescription == L10n.text("relay.error.invalid_base_url"))
        #expect(
            CodexProviderConfigError.writeFailed("disk blocked").errorDescription
                == L10n.text("relay.error.config_write_failed_format", "disk blocked")
        )
    }

    @Test
    func providerConfigDefaultURLPointsAtCodexConfigTOML() {
        let service = CodexProviderConfigService()

        #expect(service.configURLProvider().path.hasSuffix("/.codex/config.toml"))
    }

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
    func providerConfigRendersEscapedTrimmedAPIKeyWhenProvided() throws {
        let config = try CodexProviderConfig(
            providerID: "relay_1",
            name: "Relay \"Prod\"",
            baseURL: "https://relay.example.com/api/\\codex",
            wireAPI: " responses ",
            requiresOpenAIAuth: false
        )

        let rendered = config.renderTOMLBlock(apiKey: " \tsk-\"quoted\"\\key\n ")

        #expect(rendered.contains("[model_providers.relay_1]"))
        #expect(rendered.contains("name = \"Relay \\\"Prod\\\"\""))
        #expect(rendered.contains("base_url = \"https://relay.example.com/api/%5Ccodex\""))
        #expect(rendered.contains("wire_api = \"responses\""))
        #expect(rendered.contains("requires_openai_auth = false"))
        #expect(rendered.contains("experimental_bearer_token = \"sk-\\\"quoted\\\"\\\\key\""))
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
    func configMergeInsertsModelProviderBeforeExistingTablesWhenTopLevelIsMissing() throws {
        let existing = """
        [profiles.work]
        model_provider = "openai"
        """
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex"
        )

        let merged = CodexProviderConfigMerger.merge(existing: existing, provider: config)

        #expect(merged.hasPrefix("model_provider = \"mirror\"\n"))
        #expect(merged.contains("[profiles.work]\nmodel_provider = \"openai\""))
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
    func enhancedConfigMergeKeepsOpenAIProviderAndRoutesOpenAIBaseURL() throws {
        let existing = """
        model = "gpt-5.1-codex"
        model_provider = "mirror"
        openai_base_url = "https://old-relay.example.com/api/codex"

        [model_providers.other]
        name = "other"
        experimental_bearer_token = "sk-other"

        [model_providers.mirror]
        name = "old"
        base_url = "https://old.example.com/v1"
        experimental_bearer_token = "sk-old-relay"
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

        #expect(merged.contains("model = \"gpt-5.1-codex\""))
        #expect(!merged.contains("\nmodel_provider = \"mirror\""))
        #expect(!merged.hasPrefix("model_provider = \"mirror\""))
        #expect(merged.contains("openai_base_url = \"https://ai.liaryai.com/api/codex\""))
        #expect(!merged.contains("https://old-relay.example.com/api/codex"))
        #expect(!merged.contains("[model_providers.mirror]"))
        #expect(!merged.contains("experimental_bearer_token = \"sk-relay\""))
        #expect(!merged.contains("sk-old-relay"))
        #expect(merged.contains("[model_providers.other]"))
        #expect(merged.contains("experimental_bearer_token = \"sk-other\""))
    }

    @Test
    func enhancedConfigMergeAppendsOpenAIBaseURLWhenNoTableExists() throws {
        let existing = """
        model = "gpt-5.1-codex"
        """
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://relay.example.com/v1"
        )

        let merged = CodexProviderConfigMerger.mergePreservingOfficialAuth(
            existing: existing,
            provider: config,
            apiKey: "ignored"
        )

        #expect(merged == "model = \"gpt-5.1-codex\"\nopenai_base_url = \"https://relay.example.com/v1\"\n")
    }

    @Test
    func enhancedConfigMergeCreatesOpenAIBaseURLFromEmptyConfig() throws {
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://relay.example.com/v1"
        )

        let merged = CodexProviderConfigMerger.mergePreservingOfficialAuth(
            existing: "",
            provider: config,
            apiKey: "ignored"
        )

        #expect(merged == "openai_base_url = \"https://relay.example.com/v1\"\n")
    }

    @Test
    func configResetRemovesOnlyTopLevelModelProvider() {
        let existing = """
        model = "gpt-5.1-codex"
        model_provider = "mirror"
        openai_base_url = "https://ai.liaryai.com/api/codex"

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
        #expect(!reset.contains("openai_base_url"))
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
        openai_base_url = "https://ai.liaryai.com/api/codex"
        experimental_bearer_token = "sk-top-level"

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
        #expect(!reset.contains("openai_base_url"))
        #expect(!reset.contains("experimental_bearer_token = \"sk-top-level\""))
        #expect(!reset.contains("experimental_bearer_token = \"sk-relay\""))
        #expect(reset.contains("experimental_bearer_token = \"sk-other\""))
    }

    @Test
    func configResetReadsSingleQuotedActiveProviderAndRemovesItsBearerToken() {
        let existing = """
        model_provider = 'mirror'

        [model_providers.mirror]
        name = "mirror"
        experimental_bearer_token = "sk-active"

        [model_providers.other]
        name = "other"
        experimental_bearer_token = "sk-other"
        """

        let reset = CodexProviderConfigMerger.resetModelProvider(existing: existing)

        #expect(!reset.contains("model_provider = 'mirror'"))
        #expect(!reset.contains("experimental_bearer_token = \"sk-active\""))
        #expect(reset.contains("experimental_bearer_token = \"sk-other\""))
    }

    @Test
    func configResetWithUnquotedModelProviderDoesNotRemoveProviderBearerToken() {
        let existing = """
        model_provider = mirror

        [model_providers.mirror]
        name = "mirror"
        experimental_bearer_token = "sk-active"
        """

        let reset = CodexProviderConfigMerger.resetModelProvider(existing: existing)

        #expect(!reset.contains("model_provider = mirror"))
        #expect(reset.contains("experimental_bearer_token = \"sk-active\""))
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
        openai_base_url = "https://ai.liaryai.com/api/codex"

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
        #expect(!reset.contains("openai_base_url"))
        #expect(reset.contains("model = \"gpt-5.1-codex\""))
        #expect(reset.contains("[model_providers.mirror]"))
    }

    @Test
    func configServiceApplyCreatesConfigWhenFileIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-provider-apply-missing-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("nested/config.toml")
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://relay.example.com/v1"
        )
        let service = CodexProviderConfigService(configURLProvider: { configURL })

        try service.apply(provider)

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents.contains("model_provider = \"mirror\""))
        #expect(contents.contains("[model_providers.mirror]"))
    }

    @Test
    func configServiceApplyPreservingOfficialAuthCreatesConfigWhenFileIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-provider-enhanced-missing-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://relay.example.com/v1"
        )
        let service = CodexProviderConfigService(configURLProvider: { configURL })

        try service.applyPreservingOfficialAuth(provider, apiKey: "ignored")

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents == "openai_base_url = \"https://relay.example.com/v1\"\n")
    }

    @Test
    func configServiceResetReturnsWhenConfigFileIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-provider-reset-missing-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CodexProviderConfigService(configURLProvider: { configURL })

        try service.resetToDefaultModelProvider()

        #expect(!FileManager.default.fileExists(atPath: configURL.path))
    }

    @Test
    func configServiceApplyAndResetDoNotMutateOAuthAuthJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-provider-auth-isolation-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("config.toml")
        let authURL = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        model = "gpt-5.1-codex"
        """.write(to: configURL, atomically: true, encoding: .utf8)
        try """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "oauth-access-token",
            "refresh_token": "oauth-refresh-token"
          },
          "last_refresh_at": 1800000000
        }
        """.write(to: authURL, atomically: true, encoding: .utf8)
        let provider = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            requiresOpenAIAuth: true
        )
        let service = CodexProviderConfigService(configURLProvider: { configURL })

        try service.apply(provider)
        try service.applyPreservingOfficialAuth(provider, apiKey: "relay-key-\(UUID().uuidString)")
        try service.resetToDefaultModelProvider()

        let authData = try Data(contentsOf: authURL)
        let authObject = try #require(JSONSerialization.jsonObject(with: authData) as? [String: Any])
        let tokens = try #require(authObject["tokens"] as? [String: Any])
        let authText = String(data: authData, encoding: .utf8) ?? ""
        #expect(authObject["auth_mode"] as? String == "chatgpt")
        #expect(tokens.keys.contains("access_token"))
        #expect(tokens.keys.contains("refresh_token"))
        #expect((tokens["access_token"] as? String)?.isEmpty == false)
        #expect((tokens["refresh_token"] as? String)?.isEmpty == false)
        #expect(authObject["last_refresh_at"] as? Int == 1_800_000_000)
        #expect(!authText.contains("OPENAI_API_KEY"))
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
    func loginErrorsCompareOnlyUserVisibleMessage() {
        let first = CodexAPIKeyLoginError.loginFailed("same message", diagnosticLog: "first diagnostic")
        let second = CodexAPIKeyLoginError.loginFailed("same message", diagnosticLog: "second diagnostic")
        let different = CodexAPIKeyLoginError.loginFailed("different message", diagnosticLog: "first diagnostic")

        #expect(first == second)
        #expect(first != different)
        #expect(first.diagnosticLog == "first diagnostic")
    }

    @Test
    func loginErrorDescriptionIncludesUserVisibleMessage() {
        let error = CodexAPIKeyLoginError.loginFailed("visible failure", diagnosticLog: "diagnostic")

        #expect(error.errorDescription?.contains("visible failure") == true)
    }

    @Test
    func loginWithAPIKeyStringWritesTrimmedAuthJSONAndSanitizedDiagnostic() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-api-key-login-string-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CodexAPIKeyLoginService(
            authFileURLProvider: { authURL }
        )
        let apiKey = "relay-key-\(UUID().uuidString)"

        let diagnostic = try await service.login(apiKey: " \n\(apiKey)\t ")

        let data = try Data(contentsOf: authURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wroteExpectedAPIKey = object["OPENAI_API_KEY"] as? String == apiKey
        #expect(object["auth_mode"] as? String == "apikey")
        #expect(wroteExpectedAPIKey)
        #expect(diagnostic.contains("Relay API key auth diagnostic:"))
        #expect(diagnostic.contains("api_key_data_len=\(apiKey.count)"))
        #expect(diagnostic.contains("trimmed_api_key_len=\(apiKey.count)"))
        #expect(diagnostic.contains("auth_write_stage=written"))
        #expect(!diagnostic.contains(apiKey))
    }

    @Test
    func loginWithAPIKeyStringRejectsWhitespaceBeforeWritingAuthJSON() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-api-key-login-string-empty-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CodexAPIKeyLoginService(
            authFileURLProvider: { authURL }
        )

        do {
            _ = try await service.login(apiKey: " \n\t ")
            Issue.record("Expected whitespace API key string to fail before writing auth.json.")
        } catch let error as CodexAPIKeyLoginError {
            #expect(error.diagnosticLog?.contains("Relay API key auth diagnostic:") == true)
            #expect(error.diagnosticLog?.contains("api_key_data_len=0") == true)
            #expect(error.diagnosticLog?.contains("trimmed_api_key_len=0") == true)
            #expect(error.diagnosticLog?.contains("auth_write_stage=missing_api_key") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: authURL.path))
    }

    @Test
    func loginMissingAPIKeyDiagnosticUsesTildeForHomeAuthPath() async {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let service = CodexAPIKeyLoginService(
            authFileURLProvider: { homeURL }
        )

        do {
            _ = try await service.login(trimmedAPIKeyData: Data())
            Issue.record("Expected empty API key data to fail before writing auth.json.")
        } catch let error as CodexAPIKeyLoginError {
            #expect(error.diagnosticLog?.contains("auth_file_path=~") == true)
            #expect(error.diagnosticLog?.contains("auth_write_stage=missing_api_key") == true)
            #expect(error.diagnosticLog?.contains("error_description=nil") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func loginMissingAPIKeyDiagnosticUsesHomeRelativeAuthPath() async {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/auth.json")
        let service = CodexAPIKeyLoginService(
            authFileURLProvider: { authURL }
        )

        do {
            _ = try await service.login(trimmedAPIKeyData: Data())
            Issue.record("Expected empty API key data to fail before writing auth.json.")
        } catch let error as CodexAPIKeyLoginError {
            #expect(error.diagnosticLog?.contains("auth_file_path=~/.codex/auth.json") == true)
            #expect(error.diagnosticLog?.contains("auth_write_stage=missing_api_key") == true)
            #expect(error.diagnosticLog?.contains("error_description=nil") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func loginWithPreparedAPIKeyDataWritesAuthJSONDirectly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-api-key-login-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CodexAPIKeyLoginService(
            authFileURLProvider: { authURL }
        )

        let diagnostic = try await service.login(trimmedAPIKeyData: Data(" relay-token-123 \n".utf8))

        let data = try Data(contentsOf: authURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["auth_mode"] as? String == "apikey")
        #expect(object["OPENAI_API_KEY"] as? String == "relay-token-123")
        #expect(diagnostic.contains("Relay API key auth diagnostic:"))
        #expect(diagnostic.contains("api_key_data_len=18"))
        #expect(diagnostic.contains("trimmed_api_key_len=15"))
        #expect(diagnostic.contains("auth_write_stage=written"))
        #expect(!diagnostic.contains("relay-token-123"))
    }

    @Test
    func loginWithPreparedAPIKeyDataRejectsEmptyInputBeforeWritingAuthJSON() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-api-key-login-empty-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = CodexAPIKeyLoginService(
            authFileURLProvider: { authURL }
        )

        do {
            _ = try await service.login(trimmedAPIKeyData: Data(" \n\t ".utf8))
            Issue.record("Expected empty API key data to fail before writing auth.json.")
        } catch let error as CodexAPIKeyLoginError {
            #expect(error.diagnosticLog?.contains("Relay API key auth diagnostic:") == true)
            #expect(error.diagnosticLog?.contains("api_key_data_len=4") == true)
            #expect(error.diagnosticLog?.contains("trimmed_api_key_len=0") == true)
            #expect(error.diagnosticLog?.contains("auth_write_stage=missing_api_key") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: authURL.path))
    }

    @Test
    func loginReportsWriteFailureDiagnosticWithoutLeakingAPIKey() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-api-key-login-blocked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedParentURL = directory.appendingPathComponent("blocked-parent")
        try Data("not a directory".utf8).write(to: blockedParentURL)
        let authURL = blockedParentURL.appendingPathComponent("auth.json")
        let service = CodexAPIKeyLoginService(
            authFileURLProvider: { authURL }
        )
        let apiKey = "blocked-key-\(UUID().uuidString)"

        do {
            _ = try await service.login(apiKey: apiKey)
            Issue.record("Expected API key login to fail when auth parent path is a file.")
        } catch let error as CodexAPIKeyLoginError {
            #expect(error.diagnosticLog?.contains("Relay API key auth diagnostic:") == true)
            #expect(error.diagnosticLog?.contains("auth_write_stage=write_failed") == true)
            #expect(error.diagnosticLog?.contains("trimmed_api_key_len=\(apiKey.count)") == true)
            #expect(error.diagnosticLog?.contains("error_description=nil") == false)
            #expect(error.diagnosticLog?.contains(apiKey) == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: authURL.path))
    }
}
