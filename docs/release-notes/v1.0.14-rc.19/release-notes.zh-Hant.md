# CodexPoolManager v1.0.14-rc.19

發布日期：2026-07-03

## 改進

- README 的 menu bar 截圖改為使用非敏感 mock data，由真正的 `MenuBarDashboardView` SwiftUI 介面渲染產出。
- README 新增繁體中文、簡體中文、日文、韓文、法文與西班牙文的 menu bar 本地化截圖。
- 新增 gated 截圖產生測試，之後可從 App 的 SwiftUI UI 重新產生 README menu bar 截圖，不再使用手工修圖。

## 注意事項

- 此 prerelease 維持 v1.0.14-rc.18 的 App runtime 功能集，並遞增 build number 以驗證修正後的文件與 release assets。
- 截圖 mock data 為非敏感資料，不包含真實帳號。
