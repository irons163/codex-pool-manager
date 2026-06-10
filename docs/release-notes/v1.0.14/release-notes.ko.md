# CodexPoolManager v1.0.14

릴리스 날짜: 2026-06-10

## 수정 사항

- relay 계정으로 전환할 때 token vault의 API key를 switch request에 직접 전달합니다. SwiftUI 상태가 아직 반영되지 않았거나 redacted 상태여도 기존 key를 누락으로 잘못 판단하지 않습니다.
- 릴레이 API 키 계정은 추가 시 키를 토큰 보관소에 즉시 저장합니다. 따라서 계정을 만든 직후 전환해도 "API 키 필요" 오류로 실패하지 않습니다.
- `save()` 가 토큰 보관소를 정리(prune)하던 문제를 수정했습니다. 이전에는 메모리의 스냅샷이 오래되었거나 비어 있을 때(예: 시작 시 저장) 여전히 유효한 릴레이 및 ChatGPT(OAuth) API 키가 영구적으로 삭제될 수 있었고, 저장된 스냅샷은 가려져 있어 복구할 수 없었습니다. 이제 토큰은 계정 또는 그룹을 명시적으로 삭제할 때만 제거됩니다.
- 계정 전환 전에 계정 ID로 active token vault에서 relay API key를 직접 가져오도록 하여, redacted 스냅샷을 API key 누락으로 잘못 판단하지 않도록 했습니다.
- 대시보드의 메모리 상태가 redacted 계정 스냅샷만 가지고 있을 때, 계정 전환 전에 저장된 token vault에서 relay API key를 복원합니다.
- `codex login --with-api-key`를 호출하기 전에 relay API key stdin payload를 정규화했습니다. 빈 key는 Codex CLI를 실행하기 전에 거부하고, 유효한 key는 끝에 줄바꿈이 붙은 owned bytes로 전달합니다.
- relay API key 계정 전환 시 비동기 전환 흐름에 들어가기 전에 계정, provider, API key 데이터를 스냅샷하도록 강화했습니다. v1.0.13 release 빌드에서 확인된 crash를 대상으로 한 수정입니다.
- release 빌드에서 relay 계정 전환 시 남아 있던 crash 경로를 피하도록 수정했습니다. 이제 비동기 로그인 closure 안에서 API key 문자열을 다시 trim하지 않고, 준비된 API key bytes를 Codex CLI 로그인 흐름에 전달합니다.
- relay API key 폼의 추가 가능 상태 계산을 SwiftUI body 렌더링 밖으로 옮겨, 화면 업데이트 중 불필요한 문자열 trim을 줄였습니다.
- 민감 정보를 포함하지 않는 relay 전환 진단 로그를 추가했습니다. 계정 ID, token 길이, 전환 단계를 기록하되 API key 값은 저장하지 않아, release 빌드에서만 발생하는 key 누락 보고를 정확히 추적할 수 있습니다.

## 참고 사항

- 계정, API key, auth.json, config.toml 마이그레이션은 필요하지 않습니다.
- 이 prerelease는 stable 배포 전에 relay API key 전환 hotfix를 검증하기 위한 버전입니다.
- GitHub Release에 대응되는 dSYM을 함께 첨부하여 release 빌드 crash를 조사하고 symbolicated 로그를 확보할 수 있습니다.
