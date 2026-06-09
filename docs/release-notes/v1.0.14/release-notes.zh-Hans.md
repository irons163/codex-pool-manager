# CodexPoolManager v1.0.14

发布日期：2026-06-09

## 修复

- 加强中转 API key 账号切换流程，会先快照账号、provider 与 API key 数据，再进入异步切换流程。此修复针对 v1.0.13 release 版观察到的 crash。
- 修复 release 版切换中转账号时仍可能 crash 的问题；现在会把已准备好的 API key bytes 传入 Codex CLI 登录流程，不再于异步登录 closure 内重新 trim API key 字符串。
- 将中转 API key 表单可新增状态移出 SwiftUI body 计算，避免界面更新时重复进行字符串 trim。

## 注意事项

- 不需要迁移账号、API key、auth.json 或 config.toml。
- 此 prerelease 用于正式发布前验证中转 API key 切换 hotfix。
- GitHub Release 现在会附上对应的 dSYM，方便后续追查 release 版 crash 并生成可读的符号化记录。
