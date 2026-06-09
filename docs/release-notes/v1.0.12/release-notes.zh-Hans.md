# CodexPoolManager v1.0.12

发布日期：2026-06-09

## 修复

- 修复 v1.0.11 Release 版可能在启动后短时间内 crash 的问题。
- 将正式版 dashboard 启动路径恢复为更稳定的 production 路径，同时保留 XCTest 的偏好设置隔离。
- 降低 dashboard coverage helper 中 debug-only 的 MainActor warning。

## 注意事项

- 不需要迁移账号、API key、auth.json 或 config.toml。
- 建议所有 v1.0.11 用户更新到此 hotfix。
