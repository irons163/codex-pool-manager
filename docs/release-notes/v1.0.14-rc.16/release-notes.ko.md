# CodexPoolManager v1.0.14-rc.16

릴리스 날짜: 2026-06-18

## 수정 사항

- OAuth ChatGPT 계정이 refresh token, ID token, 마지막 refresh 시간을 token vault에 보존합니다.
- 사용량 동기화에서 401/403 응답이 오면 OAuth access token을 먼저 갱신한 뒤 한 번 재시도합니다.
- 로컬 auth.json 가져오기 시 refresh token과 ID token도 관리 대상 OAuth 계정에 함께 가져옵니다.
- 동기화 결과 병합 시 오래된 sync snapshot이 로컬의 더 최신 인증 정보를 덮어쓰지 않도록 했습니다.

## 참고 사항

- 이 prerelease는 stable 배포 전에 OAuth 계정 자동 갱신 안정성을 검증하기 위한 버전입니다.
- relay API key, config.toml, auth.json 마이그레이션은 필요하지 않습니다.
