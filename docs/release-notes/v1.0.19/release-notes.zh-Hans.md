# CodexPoolManager v1.0.19

发布日期：2026-08-28

## 修复

- 切换账号时会先关闭 Codex，再改写凭证，避免使用中的 session 被当成已撤销。
- 切换会写入目标账号的 refresh/id token，不再留下前一个账号的 token。
- 同时更新 Codex Keychain 与新版使用的 `current_account` 镜像文件。
