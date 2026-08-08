# CodexPoolManager v1.0.18-rc.1

リリース日：2026-08-08

## 修正

- OAuth サインイン時に、OpenAI JWT の入れ子クレーム（`https://api.openai.com/auth.chatgpt_account_id`）から ChatGPT Account ID を読み取るようにしました。
- 同期とアカウント切り替えで、保存済みの id/access token から欠けている Account ID を復元できます。
- サインイン時に OpenAI claims 内のネストされた profile email を認識します。

## Prerelease の注記

- この prerelease では、次回の正式版公開前に OAuth Account ID の取得を検証します。
