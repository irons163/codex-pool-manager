# CodexPoolManager v1.0.15

Release date: 2026-07-03

## Highlights

- Account cards now show available reset credits and each estimated reset-credit expiry.
- Minimal account cards summarize reset credits with compact date text such as `2 resets · 7/30, 8/1`.
- The menu bar dashboard now supports account group filtering, compact warning popovers, Plus/Pro badges, reset-credit expiry details, and always-visible switch buttons.
- Added localized What's New prompts after version/build updates, with a Settings action to reopen the latest feature notes.
- Improved OAuth account refresh stability and kept release notes localized across all supported languages.
- README menu bar screenshots now come from the real SwiftUI menu bar dashboard with non-sensitive mock data.

## Notes

- Reset-credit expiry is estimated from the previous successful sync plus 30 days; the actual expiry may differ.
- This stable release rolls up the validated changes from the v1.0.14 rc.16 through rc.19 prerelease cycle.
