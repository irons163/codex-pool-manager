# CodexPoolManager v1.0.14

发布日期：2026-06-10

## 修复

- 切换中转账号时会把 token vault 中的 API key 直接传入切换 request，避免 SwiftUI 状态尚未回写或已脱敏时，把既有 key 误判为缺少 API key。
- 新增中转 API key 账号时会立即把 key 写入 token vault,因此刚新增完就马上切换,不会再误报「需要 API key」。
- 修复 `save()` 会清除 token vault 的问题。此前若内存中的账号快照过期或为空（例如开机时的保存），可能永久删除仍然有效的中转与 ChatGPT (OAuth) API key，且因持久化快照已脱敏而无法恢复。现在 token 只会在你明确删除账号或分组时才会被移除。
- 切换中转账号前会按账号 ID 直接从当前 token vault 取回 relay API key，避免已遮蔽的账号快照被误判成缺少 API key。
- 当仪表板内存状态只剩已遮蔽的账号快照时，切换中转账号前会先从持久化 token vault 补回 relay API key。
- 调用 `codex login --with-api-key` 前会先规范化中转 API key 的 stdin payload：空 key 会在启动 Codex CLI 前被挡下，有效 key 会以独立 bytes 加结尾换行传入。
- 加强中转 API key 账号切换流程，会先快照账号、provider 与 API key 数据，再进入异步切换流程。此修复针对 v1.0.13 release 版观察到的 crash。
- 修复 release 版切换中转账号时仍可能 crash 的问题；现在会把已准备好的 API key bytes 传入 Codex CLI 登录流程，不再于异步登录 closure 内重新 trim API key 字符串。
- 将中转 API key 表单可新增状态移出 SwiftUI body 计算，避免界面更新时重复进行字符串 trim。
- 新增不含敏感信息的中转切换诊断日志，只记录账号 ID、token 长度与切换阶段，不保存 API key 值，方便精确定位 release 版才出现的「明明有 key 却误报缺少」问题。

## 注意事项

- 不需要迁移账号、API key、auth.json 或 config.toml。
- 此 prerelease 用于正式发布前验证中转 API key 切换 hotfix。
- GitHub Release 现在会附上对应的 dSYM，方便后续追查 release 版 crash 并生成可读的符号化记录。
