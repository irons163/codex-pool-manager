# CodexPoolManager v1.0.14-rc.16

发布日期：2026-06-18

## 修复

- OAuth ChatGPT 账号现在会在 token vault 保留 refresh token、ID token 与上次刷新时间。
- 用量同步遇到 401/403 时，会先刷新 OAuth access token，并重试一次。
- 导入本机 auth.json 时，会把 refresh token 与 ID token 一并带入受管理的 OAuth 账号。
- 合并同步结果时，不会再用较旧的同步快照覆盖本机较新的登录凭证。

## 注意事项

- 此 prerelease 用于正式发布前验证 OAuth 账号自动续期稳定性。
- 不需要迁移中转 API key、config.toml 或 auth.json。
