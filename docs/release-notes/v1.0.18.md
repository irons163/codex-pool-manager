# CodexPoolManager v1.0.18

Release date: 2026-08-09

## Fixes

- OAuth sign-in now reads ChatGPT Account ID from the nested OpenAI JWT claim (`https://api.openai.com/auth.chatgpt_account_id`).
- Sync and account switching can recover a missing Account ID from stored id/access tokens.
- Profile email nested under OpenAI claims is recognized during sign-in.
