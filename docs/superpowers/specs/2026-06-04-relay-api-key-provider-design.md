# Relay API Key Provider Design

Date: 2026-06-04

## Goal

Add support for Codex CLI custom OpenAI-compatible relay providers, such as:

```toml
model_provider = "mirror"

[model_providers.mirror]
name = "mirror"
base_url = "https://ai.liaryai.com/api/codex"
wire_api = "responses"
requires_openai_auth = true
```

The feature lets a user manage and switch to a relay/API-key-backed Codex profile from Codex Pool Manager without mixing it into the existing ChatGPT OAuth usage-sync flow.

## Non-Goals

- Do not fetch ChatGPT/Codex subscription usage for relay/API key accounts.
- Do not call the relay for usage unless the relay later exposes a dedicated usage endpoint.
- Do not hand-edit Codex auth internals when Codex CLI can perform the supported login flow.
- Do not make relay accounts candidates for automatic intelligent/focus switching in the first version.

## Account Model

Add an account credential type to `AgentAccount`:

- `chatGPTOAuth`: existing behavior, using `apiToken` as ChatGPT/OAuth access token and `chatGPTAccountID` for usage sync and auth.json switching.
- `relayAPIKey`: new behavior, using `apiToken` as the OpenAI-compatible API key stored through the existing token vault.

Add relay metadata fields to `AgentAccount`:

- `relayProviderID`, for example `mirror`.
- `relayProviderName`, defaulting to provider ID.
- `relayBaseURL`, for example `https://ai.liaryai.com/api/codex`.
- `relayWireAPI`, defaulting to `responses`.
- `relayRequiresOpenAIAuth`, defaulting to `true`.

Backward compatibility: missing `credentialType` decodes as `chatGPTOAuth`, so existing snapshots keep current behavior.

## UI

Add a compact API Key / Relay import panel in the Authentication workspace.

Fields:

- Account name.
- Provider ID.
- Base URL.
- Wire API, default `responses`.
- API key, secure entry.

Actions:

- Add or update relay account.
- Switch to relay account.

Display behavior:

- Relay cards should clearly show that usage sync is unavailable.
- Relay accounts can be manually switched.
- Relay accounts are excluded from automatic intelligent/focus candidates until manual quota support or relay usage sync exists.

## Switching Flow

When switching to a `relayAPIKey` account:

1. Validate provider ID, base URL, and API key are present.
2. Update `~/.codex/config.toml`:
   - Set top-level `model_provider = "<providerID>"`.
   - Add or update `[model_providers.<providerID>]`.
   - Write `name`, `base_url`, `wire_api`, and `requires_openai_auth`.
   - Preserve unrelated user config as much as possible.
3. Authenticate Codex through the supported CLI path:

```bash
printf '%s' "$OPENAI_API_KEY" | codex login --with-api-key
```

Do not write `~/.codex/auth.json` directly for API key login.

The existing OAuth switch path remains unchanged and continues to rewrite the selected `auth.json` access token/account id.

## Config Writer

Create a focused service, tentatively `CodexProviderConfigService`, responsible for reading and updating Codex `config.toml`.

Initial implementation can avoid a full TOML dependency by using a constrained merge strategy:

- Preserve the original file text.
- Replace an existing top-level `model_provider = ...` outside any table, or insert one near the top if missing.
- Replace an existing `[model_providers.<providerID>]` table block, or append a new block at the end.
- Leave other provider tables and unrelated config untouched.

Tests should cover:

- Empty config.
- Existing top-level `model_provider`.
- Existing same provider table.
- Existing other provider tables.
- Provider IDs containing invalid TOML bare-key characters should be rejected in v1.

## API Key Storage

Use the existing `AccountTokenVault` path for the API key, because account tokens are already redacted from snapshots and stored separately from the account snapshot.

Export/import behavior:

- Default backup/export remains redacted.
- Refetchable or non-redacted export can include the key only when existing export code already allows sensitive tokens.
- UI should not display the full key after save.

## Usage Sync Behavior

`relayAPIKey` accounts do not support current usage sync.

During usage sync:

- Skip relay accounts before checking `apiToken` or `chatGPTAccountID`.
- Set a stable, non-alarming exclusion reason such as `API key relay account: usage sync unavailable`.
- Do not count this as an error in the global sync status.

Automatic switching:

- Exclude relay accounts from automatic intelligent/focus switching in v1.
- Manual switching remains allowed.

Future extension:

- If a relay exposes a usage endpoint, add a separate `RelayUsageClient` rather than forcing relay accounts through `OpenAICodexUsageClient`.

## Error Handling

Surface user-friendly errors for:

- Missing API key.
- Invalid provider ID.
- Invalid base URL.
- `~/.codex/config.toml` write failure.
- `codex login --with-api-key` failure.
- Missing Codex CLI binary.

Switching should not partially report success if config update succeeds but login fails. The activity log should state which step failed.

## Testing

Add unit tests for:

- `AgentAccount` decoding defaults existing accounts to `chatGPTOAuth`.
- Relay account token redaction and token-vault load/save.
- Relay accounts are skipped by usage sync with the explicit unavailable reason.
- Relay accounts are excluded from automatic switching candidates.
- Codex provider config generation/merge behavior.
- Relay switch coordinator validates input and reports failures.

Add one smoke/view test for the relay account form if the UI can be covered without brittle layout assertions.

## Release Notes

Mention that Codex Pool Manager can now switch Codex CLI to an OpenAI-compatible relay provider/API key profile, while usage sync remains available only for ChatGPT OAuth accounts.
