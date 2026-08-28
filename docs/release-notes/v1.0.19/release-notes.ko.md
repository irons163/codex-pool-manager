# CodexPoolManager v1.0.19

출시일: 2026-08-28

## 수정

- 계정 전환 시 자격 증명을 다시 쓰기 전에 Codex를 종료하여, 실행 중인 세션이 취소된 것으로 처리되지 않게 했습니다.
- 전환 시 대상 계정의 refresh/id 토큰을 기록하고 이전 계정의 토큰을 남기지 않습니다.
- Codex Keychain과 새 Codex 빌드가 사용하는 `current_account` 미러도 함께 갱신합니다.
