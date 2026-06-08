# CodexPoolManager v1.0.11

发布日期：2026-06-08

## 重点更新

- 新增 API Key 中转账号，可手动将 Codex CLI 切换到使用 API key 的中转 provider。
- 将验证流程分成两条更清楚的路线：OAuth / 订阅账号与 API Key 中转账号。
- 新增“保留既有历史记录”模式：保留 Codex 既有历史记录，同时将 API 请求导向中转 Base URL。
- 修复从中转账号切回订阅账号时，OAuth 验证资料与 provider 设置没有干净还原的问题。
- API key 中转账号会固定排在账号列表最后，并排除于用量同步与自动切换之外。
- 改善中转设置表单：Base URL 改为主要必填字段、API 格式加入说明，且 Base URL 默认保持空白。
- 补齐中转账号 UI 与 release notes 的多国语言内容。

## 注意事项

- API key 中转账号不提供 ChatGPT 订阅用量数据，因此仅支持手动切换。
- 若启用“保留既有历史记录”，设置会在下次切换到中转账号时生效。
- 不需要手动迁移资料。
