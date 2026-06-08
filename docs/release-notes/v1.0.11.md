# CodexPoolManager v1.0.11

Release date: 2026-06-08

## Highlights

- Added API Key Relay accounts for manually switching Codex CLI to relay providers that use an API key.
- Split authentication into two clearer routes: OAuth / subscription accounts and API Key Relay accounts.
- Added a history-preserving relay mode that keeps existing Codex history visible while routing API requests through the relay Base URL.
- Fixed relay-to-subscription switching so OAuth auth metadata and provider config are restored cleanly.
- Kept relay API key accounts at the end of the account list and excluded them from usage sync / automatic switching.
- Improved the relay setup form: Base URL is now a required primary field, API Format has an inline explanation, and Base URL starts empty by default.
- Localized the relay account UI and release notes across supported languages.

## Notes

- Relay API key accounts are manual-switch only because they do not provide ChatGPT subscription usage data.
- If history-preserving mode is enabled, it takes effect the next time you switch to a relay account.
- No manual migration is required.
