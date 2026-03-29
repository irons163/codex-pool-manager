# Codex Pool Manager

複数の Codex アカウントを管理し、アクティブアカウントをすばやく切り替え、同一ダッシュボードで利用状況を確認できる macOS アプリです。

言語: [English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## 主な機能

- マルチアカウントプール管理
- ワンクリックでアクティブアカウント切り替え
- 利用状況ダッシュボード（有料アカウント枠を含む）
- ローカル OAuth アカウント取り込み
- ローカルプールデータのバックアップ/復元
- 多言語 UI

## プロジェクト構成

- `CodexPoolManager/`: アプリ本体
- `CodexPoolManagerTests/`: ユニットテスト
- `CodexPoolManagerUITests/`: UI テスト
- `.github/workflows/release-dmg.yml`: DMG リリースワークフロー
- `scripts/build_and_notarize_dmg.sh`: ビルド + notarize スクリプト

## 要件

- macOS
- Xcode 16+

## ローカル実行

```bash
open CodexPoolManager.xcodeproj
```

Xcode で `CodexPoolManager` スキームを選んでビルド/実行します。

## DMG リリース

CI での notarized DMG リリースは [RELEASE_DMG.md](RELEASE_DMG.md) を参照してください。
