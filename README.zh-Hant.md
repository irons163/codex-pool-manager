# Codex Pool Manager

一個 macOS 應用程式，用來管理多個 Codex 帳號、快速切換目前帳號，並在同一個儀表板查看用量。

語言： [English](README.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## 截圖

（以下為 mock 測試資料）

![OpenAI Reset Alert](docs/images/openai-reset-alert.png)

## 功能

- 多帳號池管理
- 一鍵切換目前啟用帳號
- 用量儀表板（含付費帳號視窗）
- OpenAI Reset Alert 工作區（監測付費帳號提前重置訊號）
- 本機 OAuth 帳號匯入
- 本機池資料備份與還原
- 多語系介面

## 工作區

- OpenAI Reset Alert：追蹤付費帳號週重置與 5 小時重置，若早於預期發生則提醒。

## 專案結構

- `CodexPoolManager/`：App 原始碼
- `CodexPoolManagerTests/`：單元測試
- `CodexPoolManagerUITests/`：UI 測試
- `.github/workflows/release-dmg.yml`：DMG 發版流程
- `scripts/build_and_notarize_dmg.sh`：建置與 notarize 腳本

## 需求

- macOS
- Xcode 16+

## 本機執行

```bash
open CodexPoolManager.xcodeproj
```

在 Xcode 使用 `CodexPoolManager` scheme 建置與執行。

## DMG 發版

CI 自動 notarized DMG 發版請參考 [RELEASE_DMG.md](RELEASE_DMG.md)。
