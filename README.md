# Codex Pool Manager

A macOS app for managing multiple Codex accounts, switching active auth quickly, and tracking usage in one dashboard.

Languages: [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## App Screenshot

![Codex Pool Manager Screenshot](docs/images/app-screenshot.png)

## Features

- Multi-account pool management
- One-click active account switching
- Usage dashboard (including paid account windows)
- Local OAuth account import
- Backup and restore for local pool data
- UI localization support

## Project Structure

- `CodexPoolManager/`: App sources
- `CodexPoolManagerTests/`: Unit tests
- `CodexPoolManagerUITests/`: UI tests
- `.github/workflows/release-dmg.yml`: DMG release workflow
- `scripts/build_and_notarize_dmg.sh`: Build + notarize script

## Requirements

- macOS
- Xcode 16+

## Run Locally

```bash
open CodexPoolManager.xcodeproj
```

Build/run with the `CodexPoolManager` scheme in Xcode.

## Release DMG

For CI notarized DMG release, see [RELEASE_DMG.md](RELEASE_DMG.md).
