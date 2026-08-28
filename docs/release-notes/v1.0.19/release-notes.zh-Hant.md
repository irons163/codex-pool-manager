# CodexPoolManager v1.0.19

發布日期：2026-08-28

## 修正

- 切換帳號時會先關閉 Codex，再改寫憑證，避免使用中的 session 被當成已撤銷。
- 切換會寫入目標帳號的 refresh/id token，不再留下前一個帳號的 token。
- 同時更新 Codex Keychain 與新版使用的 `current_account` 鏡像檔。
