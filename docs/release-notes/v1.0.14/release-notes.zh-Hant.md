# CodexPoolManager v1.0.14

發布日期：2026-06-10

## 修正

- 切換中轉帳號時會把 token vault 中的 API key 直接傳入切換 request，避免 SwiftUI 狀態尚未回寫或已遮蔽時，把既有 key 誤判為缺少 API key。
- 新增中轉 API key 帳號時會立即把 key 寫入 token vault,因此剛新增完就馬上切換,不會再誤報「需要 API key」。
- 修正 `save()` 會清除 token vault 的問題。先前若記憶體中的帳號快照過期或為空（例如開機時的存檔），可能永久刪除仍然有效的中轉與 ChatGPT (OAuth) API key，且因持久化快照已遮蔽而無法復原。現在 token 只會在你明確刪除帳號或群組時才會被移除。
- 切換中轉帳號前會依帳號 ID 直接從作用中的 token vault 取回 relay API key，避免已遮蔽的帳號快照被誤判成缺少 API key。
- 當儀表板記憶體狀態只剩已遮蔽的帳號快照時，切換中轉帳號前會先從持久化 token vault 補回 relay API key。
- 呼叫 `codex login --with-api-key` 前會先正規化中轉 API key 的 stdin payload：空 key 會在啟動 Codex CLI 前被擋下，有效 key 會以獨立 bytes 加結尾換行傳入。
- 加強中轉 API key 帳號切換流程，會先快照帳號、provider 與 API key 資料，再進入非同步切換流程。此修正針對 v1.0.13 release 版觀察到的 crash。
- 修正 release 版切換中轉帳號時仍可能 crash 的問題；現在會把已準備好的 API key bytes 傳入 Codex CLI 登入流程，不再於非同步登入 closure 內重新 trim API key 字串。
- 將中轉 API key 表單可新增狀態移出 SwiftUI body 計算，避免畫面更新時重複進行字串 trim。
- 新增不含敏感資訊的中轉切換診斷日誌，只記錄帳號 ID、token 長度與切換階段，不保存 API key 值，方便精準定位 release 版才出現的「明明有 key 卻誤報缺少」問題。

## 注意事項

- 不需要遷移帳號、API key、auth.json 或 config.toml。
- 此 prerelease 用於正式發布前驗證中轉 API key 切換 hotfix。
- GitHub Release 現在會附上對應的 dSYM，方便後續追查 release 版 crash 並產生可讀的符號化紀錄。
