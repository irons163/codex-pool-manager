# CodexPoolManager v1.0.14

릴리스 날짜: 2026-06-10

## 수정 사항

- 대시보드의 메모리 상태가 redacted 계정 스냅샷만 가지고 있을 때, 계정 전환 전에 저장된 token vault에서 relay API key를 복원합니다.
- `codex login --with-api-key`를 호출하기 전에 relay API key stdin payload를 정규화했습니다. 빈 key는 Codex CLI를 실행하기 전에 거부하고, 유효한 key는 끝에 줄바꿈이 붙은 owned bytes로 전달합니다.
- relay API key 계정 전환 시 비동기 전환 흐름에 들어가기 전에 계정, provider, API key 데이터를 스냅샷하도록 강화했습니다. v1.0.13 release 빌드에서 확인된 crash를 대상으로 한 수정입니다.
- release 빌드에서 relay 계정 전환 시 남아 있던 crash 경로를 피하도록 수정했습니다. 이제 비동기 로그인 closure 안에서 API key 문자열을 다시 trim하지 않고, 준비된 API key bytes를 Codex CLI 로그인 흐름에 전달합니다.
- relay API key 폼의 추가 가능 상태 계산을 SwiftUI body 렌더링 밖으로 옮겨, 화면 업데이트 중 불필요한 문자열 trim을 줄였습니다.

## 참고 사항

- 계정, API key, auth.json, config.toml 마이그레이션은 필요하지 않습니다.
- 이 prerelease는 stable 배포 전에 relay API key 전환 hotfix를 검증하기 위한 버전입니다.
- GitHub Release에 대응되는 dSYM을 함께 첨부하여 release 빌드 crash를 조사하고 symbolicated 로그를 확보할 수 있습니다.
