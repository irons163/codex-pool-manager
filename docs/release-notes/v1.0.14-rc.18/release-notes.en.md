# CodexPoolManager v1.0.14-rc.18

Release date: 2026-07-02

## Improvements

- Added reset-credit availability to main-window account cards.
- Regular account cards now list each reset credit's estimated expiry time.
- `Minimal` account cards summarize reset credits with compact date text such as `2 resets · 7/30, 8/1`.
- Added a localized `What's New` prompt after version/build changes, with a Settings entry to reopen the latest feature notes.
- Localized the new feature prompt across all supported app languages.
- Updated README documentation in all supported languages for reset-credit display and new feature prompts.

## Notes

- Reset-credit expiry is estimated from the previous successful sync plus 30 days; the actual expiry may differ.
- This prerelease is intended to validate main-window reset-credit display and localized feature prompts before a stable rollout.
