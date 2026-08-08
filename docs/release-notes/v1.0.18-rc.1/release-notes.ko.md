# CodexPoolManager v1.0.18-rc.1

출시일: 2026-08-08

## 수정

- OAuth 로그인 시 OpenAI JWT 중첩 클레임(`https://api.openai.com/auth.chatgpt_account_id`)에서 ChatGPT Account ID를 읽습니다.
- 동기화와 계정 전환 시 저장된 id/access token에서 누락된 Account ID를 복구할 수 있습니다.
- 로그인 시 OpenAI claims에 중첩된 profile email을 인식합니다.

## Prerelease 참고

- 이번 prerelease에서는 다음 정식 출시 전에 OAuth Account ID 수집을 검증합니다.
