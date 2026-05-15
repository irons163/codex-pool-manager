import Foundation

enum OAuthAccountUpsertResolver {
    static func resolveExistingAccountID(
        in accounts: [AgentAccount],
        chatGPTAccountID: String?,
        accessToken: String,
        identityScope: String?
    ) -> UUID? {
        if let normalizedAccountID = normalized(chatGPTAccountID) {
            let normalizedScope = AgentAccount.normalizedIdentityScope(identityScope ?? AgentAccount.personalIdentityScope)
            let candidates = accounts.filter { normalized($0.chatGPTAccountID) == normalizedAccountID }

            if let scopedMatch = candidates.first(where: {
                AgentAccount.normalizedIdentityScope($0.identityScope) == normalizedScope
            }) {
                return scopedMatch.id
            }

            return nil
        }

        if let byToken = accounts.first(where: { !$0.apiToken.isEmpty && $0.apiToken == accessToken }) {
            return byToken.id
        }

        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
