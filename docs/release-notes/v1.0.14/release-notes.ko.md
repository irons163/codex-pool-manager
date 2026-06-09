# CodexPoolManager v1.0.14

릴리스 날짜: 2026-06-09

## 수정 사항

- relay API key 계정 전환 시 비동기 전환 흐름에 들어가기 전에 계정, provider, API key 데이터를 스냅샷하도록 강화했습니다. v1.0.13 release 빌드에서 확인된 crash를 대상으로 한 수정입니다.
- relay API key 폼의 추가 가능 상태 계산을 SwiftUI body 렌더링 밖으로 옮겨, 화면 업데이트 중 불필요한 문자열 trim을 줄였습니다.

## 참고 사항

- 계정, API key, auth.json, config.toml 마이그레이션은 필요하지 않습니다.
- 이 prerelease는 stable 배포 전에 relay API key 전환 hotfix를 검증하기 위한 버전입니다.
- GitHub Release에 대응되는 dSYM을 함께 첨부하여 release 빌드 crash를 조사하고 symbolicated 로그를 확보할 수 있습니다.
