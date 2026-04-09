# Codex Pool Manager

一个 macOS 应用，用于管理多个 Codex 账号、快速切换当前账号，并在同一仪表板查看用量。

语言： [English](README.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## 截图

（以下为 mock 测试数据）

![OpenAI Reset Alert](docs/images/openai-reset-alert.png)

## 功能

- 多账号池管理
- 一键切换当前启用账号
- 用量仪表板（含付费账号窗口）
- OpenAI Reset Alert 工作区（监测付费账号提前重置信号）
- 本地 OAuth 账号导入
- 本地池数据备份与恢复
- 多语言界面

## 工作区

- OpenAI Reset Alert：追踪付费账号周重置与 5 小时重置，若早于预期发生则提醒。

## 项目结构

- `CodexPoolManager/`：App 源码
- `CodexPoolManagerTests/`：单元测试
- `CodexPoolManagerUITests/`：UI 测试
- `.github/workflows/release-dmg.yml`：DMG 发布流程
- `scripts/build_and_notarize_dmg.sh`：构建与 notarize 脚本

## 环境要求

- macOS
- Xcode 16+

## 本地运行

```bash
open CodexPoolManager.xcodeproj
```

在 Xcode 中使用 `CodexPoolManager` scheme 构建和运行。

## DMG 发布

CI 自动 notarized DMG 发布请参考 [RELEASE_DMG.md](RELEASE_DMG.md)。
