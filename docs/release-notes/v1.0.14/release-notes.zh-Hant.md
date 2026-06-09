# CodexPoolManager v1.0.14

發布日期：2026-06-09

## 修正

- 加強中轉 API key 帳號切換流程，會先快照帳號、provider 與 API key 資料，再進入非同步切換流程。此修正針對 v1.0.13 release 版觀察到的 crash。
- 修正 release 版切換中轉帳號時仍可能 crash 的問題；現在會把已準備好的 API key bytes 傳入 Codex CLI 登入流程，不再於非同步登入 closure 內重新 trim API key 字串。
- 將中轉 API key 表單可新增狀態移出 SwiftUI body 計算，避免畫面更新時重複進行字串 trim。

## 注意事項

- 不需要遷移帳號、API key、auth.json 或 config.toml。
- 此 prerelease 用於正式發布前驗證中轉 API key 切換 hotfix。
- GitHub Release 現在會附上對應的 dSYM，方便後續追查 release 版 crash 並產生可讀的符號化紀錄。
