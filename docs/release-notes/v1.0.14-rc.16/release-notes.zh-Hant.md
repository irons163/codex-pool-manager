# CodexPoolManager v1.0.14-rc.16

發布日期：2026-06-18

## 修正

- OAuth ChatGPT 帳號現在會在 token vault 保留 refresh token、ID token 與上次刷新時間。
- 用量同步遇到 401/403 時，會先刷新 OAuth access token，並重試一次。
- 匯入本機 auth.json 時，會把 refresh token 與 ID token 一併帶入受管理的 OAuth 帳號。
- 同步結果合併時，不會再用較舊的同步快照覆蓋本機較新的登入憑證。

## 注意事項

- 此 prerelease 用於正式發布前驗證 OAuth 帳號自動續期穩定性。
- 不需要遷移中轉 API key、config.toml 或 auth.json。
