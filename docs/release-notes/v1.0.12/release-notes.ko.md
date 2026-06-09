# CodexPoolManager v1.0.12

릴리스 날짜: 2026-06-09

## 수정 사항

- v1.0.11 Release 빌드에서 실행 직후 잠시 뒤 crash가 발생할 수 있던 문제를 수정했습니다.
- XCTest 환경의 preference 격리는 유지하면서, 정식 dashboard 시작 경로를 더 안정적인 production 경로로 되돌렸습니다.
- dashboard coverage helper의 debug-only MainActor warning을 줄였습니다.

## 참고 사항

- 계정, API key, auth.json, config.toml 마이그레이션은 필요하지 않습니다.
- v1.0.11 사용자는 이 hotfix로 업데이트하는 것을 권장합니다.
