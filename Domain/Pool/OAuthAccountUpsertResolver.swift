import Foundation

enum OAuthAccountUpsertResolver {
    static func resolveExistingAccountID(
        in accounts: [AgentAccount],
        chatGPTAccountID: String?,
        accessToken: String,
        identityScope: String?,
        email: String? = nil,
        idToken: String? = nil
    ) -> UUID? {
        func matchesUser(_ account: AgentAccount) -> Bool {
            let incoming = OAuthIDTokenClaimsParser.parse(tokens: OAuthTokens(accessToken: accessToken, refreshToken: nil, idToken: idToken))
            let existing = OAuthIDTokenClaimsParser.parse(tokens: OAuthTokens(accessToken: account.apiToken, refreshToken: nil, idToken: account.oauthIDToken))
            let incomingEmail = OAuthIDTokenClaimsParser.normalizedEmail(email ?? incoming?.email)
            let existingEmail = OAuthIDTokenClaimsParser.normalizedEmail(account.email ?? existing?.email)
            if let incomingEmail, let existingEmail, incomingEmail != existingEmail { return false }
            let hasIncomingUser = incomingEmail != nil || incoming?.userID != nil || incoming?.subject != nil
            return OAuthIDTokenClaimsParser.matchesUser(
                of: account, accessToken: accessToken, idToken: idToken,
                requireProof: hasIncomingUser && !(incomingEmail != nil && incomingEmail == existingEmail)
            )
        }
        if let normalizedAccountID = normalized(chatGPTAccountID) {
            let normalizedScope = AgentAccount.normalizedIdentityScope(identityScope ?? AgentAccount.personalIdentityScope)
            let candidates = accounts.filter { normalized($0.chatGPTAccountID) == normalizedAccountID }

            if let scopedMatch = candidates.first(where: {
                AgentAccount.normalizedIdentityScope($0.identityScope) == normalizedScope && matchesUser($0)
            }) {
                return scopedMatch.id
            }

            return nil
        }

        if let byToken = accounts.first(where: { !$0.apiToken.isEmpty && $0.apiToken == accessToken && matchesUser($0) }) {
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
