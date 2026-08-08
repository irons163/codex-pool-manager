# CodexPoolManager v1.0.18-rc.1

发布日期：2026-08-08

## 修复

- OAuth 登录现在会从 OpenAI JWT 嵌套字段读取 ChatGPT Account ID（`https://api.openai.com/auth.chatgpt_account_id`）。
- 同步与账号切换可从已保存的 id/access token 回填缺少的 Account ID。
- 登录时可识别 OpenAI claims 嵌套的 profile email。

## Prerelease 说明

- 此 prerelease 用于验证 OAuth Account ID 提取，再进入正式版发布。
