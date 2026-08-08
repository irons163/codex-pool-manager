# CodexPoolManager v1.0.18-rc.1

發布日期：2026-08-08

## 修正

- OAuth 登入現在會從 OpenAI JWT 巢狀欄位讀取 ChatGPT Account ID（`https://api.openai.com/auth.chatgpt_account_id`）。
- 同步與帳號切換可從已儲存的 id/access token 回填缺少的 Account ID。
- 登入時可辨識 OpenAI claims 巢狀的 profile email。

## Prerelease 說明

- 此 prerelease 用於驗證 OAuth Account ID 擷取，再進入正式版發布。
