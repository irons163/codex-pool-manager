# CodexPoolManager v1.0.11

發布日期：2026-06-08

## 重點更新

- 新增 API Key 中轉帳號，可手動將 Codex CLI 切換到使用 API key 的中轉 provider。
- 將驗證流程分成兩條更清楚的路線：OAuth / 訂閱帳號與 API Key 中轉帳號。
- 新增「保留既有歷史紀錄」模式：保留 Codex 既有歷史紀錄，同時將 API 請求導向中轉 Base URL。
- 修正從中轉帳號切回訂閱帳號時，OAuth 驗證資料與 provider 設定沒有乾淨還原的問題。
- API key 中轉帳號會固定排在帳號列表最後，並排除於用量同步與自動切換之外。
- 改善中轉設定表單：Base URL 改為主要必填欄位、API 格式加入說明，且 Base URL 預設保持空白。
- 補齊中轉帳號 UI 與 release notes 的多國語言內容。

## 注意事項

- API key 中轉帳號不提供 ChatGPT 訂閱用量資料，因此僅支援手動切換。
- 若啟用「保留既有歷史紀錄」，設定會在下次切換到中轉帳號時生效。
- 不需要手動遷移資料。
