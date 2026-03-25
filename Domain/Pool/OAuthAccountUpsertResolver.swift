import Foundation

enum OAuthAccountUpsertResolver {
    static func resolveExistingAccountID(
        in accounts: [AgentAccount],
        chatGPTAccountID: String?,
        accessToken: String,
        email: String?
    ) -> UUID? {
        if let chatGPTAccountID,
           !chatGPTAccountID.isEmpty,
           let byAccountID = accounts.first(where: { $0.chatGPTAccountID == chatGPTAccountID }) {
            return byAccountID.id
        }

        if let byToken = accounts.first(where: { !$0.apiToken.isEmpty && $0.apiToken == accessToken }) {
            return byToken.id
        }

        if let email,
           !email.isEmpty,
           let byEmailName = accounts.first(where: { $0.name.caseInsensitiveCompare(email) == .orderedSame }) {
            return byEmailName.id
        }

        return nil
    }
}
