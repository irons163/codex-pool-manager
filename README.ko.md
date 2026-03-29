# Codex Pool Manager

여러 Codex 계정을 관리하고, 활성 계정을 빠르게 전환하며, 하나의 대시보드에서 사용량을 확인할 수 있는 macOS 앱입니다.

언어: [English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Español](README.es.md)

## 기능

- 멀티 계정 풀 관리
- 원클릭 활성 계정 전환
- 사용량 대시보드(유료 계정 윈도우 포함)
- 로컬 OAuth 계정 가져오기
- 로컬 풀 데이터 백업/복원
- 다국어 UI

## 프로젝트 구조

- `CodexPoolManager/`: 앱 소스
- `CodexPoolManagerTests/`: 단위 테스트
- `CodexPoolManagerUITests/`: UI 테스트
- `.github/workflows/release-dmg.yml`: DMG 릴리스 워크플로
- `scripts/build_and_notarize_dmg.sh`: 빌드 + notarize 스크립트

## 요구 사항

- macOS
- Xcode 16+

## 로컬 실행

```bash
open CodexPoolManager.xcodeproj
```

Xcode에서 `CodexPoolManager` 스킴으로 빌드/실행하세요.

## DMG 릴리스

CI notarized DMG 릴리스는 [RELEASE_DMG.md](RELEASE_DMG.md)를 참고하세요.
