# CodexPoolManager v1.0.12

發布日期：2026-06-09

## 修正

- 修正 v1.0.11 Release 版可能在啟動後短時間內 crash 的問題。
- 將正式版 dashboard 啟動路徑恢復為較穩定的 production 路徑，同時保留 XCTest 的偏好設定隔離。
- 降低 dashboard coverage helper 中 debug-only 的 MainActor warning。

## 注意事項

- 不需要遷移帳號、API key、auth.json 或 config.toml。
- 建議所有 v1.0.11 使用者更新到此 hotfix。
