# CodexPoolManager v1.0.14-rc.19

发布日期：2026-07-03

## 改进

- README 的 menu bar 截图改为使用非敏感 mock data，由真正的 `MenuBarDashboardView` SwiftUI 界面渲染生成。
- README 新增繁体中文、简体中文、日文、韩文、法文与西班牙文的 menu bar 本地化截图。
- 新增 gated 截图生成测试，之后可从 App 的 SwiftUI UI 重新生成 README menu bar 截图，不再使用手工修图。

## 注意事项

- 此 prerelease 保持 v1.0.14-rc.18 的 App runtime 功能集，并递增 build number 以验证修正后的文档与 release assets。
- 截图 mock data 为非敏感数据，不包含真实账号。
