# CodexPoolManager v1.0.18

リリース日：2026-08-09

## 修正

- OAuth サインイン時に、OpenAI JWT の入れ子クレーム（`https://api.openai.com/auth.chatgpt_account_id`）から ChatGPT Account ID を読み取るようにしました。
- 同期とアカウント切り替えで、保存済みの id/access token から欠けている Account ID を復元できます。
- サインイン時に OpenAI claims 内のネストされた profile email を認識します。
