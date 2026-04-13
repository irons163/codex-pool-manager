# Codex Pool Manager

Codex Pool Manager는 하나의 제어 패널에서 Codex/OpenAI OAuth 계정 풀을 운영하기 위한 macOS 앱입니다.

주요 기능:
- 계정별 쿼터와 잔여 사용량 추적
- 활성 인증 계정 빠른 전환
- 지능형 정책 기반 자동 로테이션
- 데스크톱 Widget/메뉴바 상태 모니터링
- 백업/내보내기를 통한 복구

언어: [English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Español](README.es.md)

## 목차

1. [스크린샷](#스크린샷)
2. [핵심 기능](#핵심-기능)
3. [지능형 전환 동작 방식](#지능형-전환-동작-방식)
4. [Widget + 메뉴바](#widget--메뉴바)
5. [인증 및 계정 가져오기](#인증-및-계정-가져오기)
6. [워크스페이스](#워크스페이스)
7. [설치](#설치)
8. [소스에서 빌드](#소스에서-빌드)
9. [Release DMG 파이프라인](#release-dmg-파이프라인)
10. [프로젝트 구조](#프로젝트-구조)
11. [테스트](#테스트)
12. [문제 해결](#문제-해결)
13. [보안 및 개인정보](#보안-및-개인정보)
14. [기여](#기여)

## 스크린샷

아래 이미지는 mock 또는 비민감 테스트 데이터입니다.

### 메인 대시보드 (Dark, Mock)

![Main Dashboard (Dark, Mock Data)](docs/images/app-screenshot.png)

### 상단 요약 (Light, Mock)

![Header Overview (Light, Mock Data)](docs/images/dashboard-light.png)

### 메뉴바 상태 (Mock)

![Menu Bar Status](docs/images/menu-bar.png)

### Widget (빈 상태 예시, Mock)

![Widget Empty State](docs/images/widget-empty-state.png)

### OpenAI Reset Alert (Mock)

![OpenAI Reset Alert](docs/images/openai-reset-alert.png)

## 핵심 기능

### 1) 계정 풀 관리

- 계정 추가/편집/복제/삭제
- 그룹 관리 (`Add`, `Rename`, `Delete`)
- 그룹 삭제 시 해당 그룹 계정도 함께 삭제
- 대규모 풀을 위한 정렬/레이아웃 제공
- `Accounts`/`Available`/`Pool Usage` 통계는 중복 ID를 제거해 계산

### 2) 전환 모드

- `Intelligent`: 잔여 용량과 정책 임계값으로 최적 계정 자동 선택
- `Manual`: 사용자가 선택한 계정을 유지
- `Focus`: 현재 계정을 고정하고 자동 로테이션 비활성화

### 3) 사용량 동기화 및 진단

- 대상 계정의 Codex/OpenAI 사용량 동기화
- 동기화 제외 조건 처리 (token 없음, account id 없음, API/네트워크 오류)
- 마지막 성공 동기화 시각 및 오류 상세 표시
- 진단용 raw usage JSON / switch log 제공

### 4) OAuth 로그인 플로우

- 앱 내 OAuth 로그인 + 즉시 가져오기
- 수동 플로우 (Authorization URL 복사 → callback URL 붙여넣기 → Import)
- 일반 로컬 경로에서 auth 데이터 검색
- 로컬 OAuth sessions/accounts를 관리 풀로 가져오기

### 5) 데스크톱 연동

- macOS 알림 (동기화 실패/복구, 저사용량, 자동 전환 결과)
- 잔여 상태를 보여주는 메뉴바 항목
- 빠른 확인용 macOS Widget

### 6) 백업 및 복구

- JSON 스냅샷 내보내기
- 재조회용 스냅샷 내보내기(민감 데이터 포함 가능)
- JSON 스냅샷 가져오기(마이그레이션/복구)

### 7) UI 및 다국어

- 다크 모드 + 라이트 모드
- 앱 설정에서 언어 전환
- App/Widget 시간 문자열 로케일 포맷 적용

### 8) 사용량 분석 및 Schedule 계획

- 여러 계정의 리셋 시간을 한눈에 보는 `Schedule` 워크스페이스 제공
- 일간/주간 사용량 분석으로 사용 패턴 파악
- 계정 간 커버리지 공백 구간을 표시해 사용 불가 시간대 사전 확인
- 계정별 추세선, 임계값 이벤트, 이상 징후 요약 제공
- 분석 데이터를 JSON/CSV로 내보내기 가능

### 9) OpenAI 리셋 모니터링

- 유료 계정용 `OpenAI Reset Alert` 워크스페이스 제공
- 주간 리셋과 5시간 리셋을 동시에 추적
- 예상보다 이른 리셋을 감지(허용 오차 설정 가능)
- 데스크톱 알림 및 이벤트 히스토리 제공

## 지능형 전환 동작 방식

런타임에서 실제로 어떻게 동작하는지 설명합니다.

### 계정 자격

**동기화/스케줄 제외가 아닌** 계정만 자동 전환 후보가 됩니다.

제외 예시:
- API token 없음
- ChatGPT account id 없음
- 동기화 오류 상태

### 유료/비유료 잔여 로직

- 비유료: 주간 잔여 비율(`remainingUnits / quota`) 기준
- 유료(기본): **5시간 잔여**% 기준
- 유료 예외: 주간 잔여가 `0%`면 주간 잔여를 기준으로 판단

### 후보 선택

후보 중 지능형 잔여 비율이 가장 높은 계정을 선택합니다.

주간 잔여 `<= 0` 계정은 후보에서 제외됩니다.

### 전환 트리거 조건

`Intelligent` 모드에서 다음 조건을 모두 만족해야 전환됩니다.

1. 유효한 후보 존재
2. 현재 계정이 전환 임계값 미만
3. 후보가 현재 계정보다 유리
4. 쿨다운 경과

### Focus 모드 동작

`Focus`로 전환하면 현재 계정을 고정해 예기치 않은 변경을 방지합니다.

Focus 모드에서는 지능형 자동 전환이 실행되지 않습니다.

### 저사용량 알림 임계값은 별도

두 임계값은 서로 독립입니다.

- Intelligent switch threshold: **전환 허용 조건**
- Low remaining alert threshold: **경고/알림 표시 조건**

## Widget + 메뉴바

### Widget

- 메인 앱이 제공하는 로컬 bridge 스냅샷을 사용
- 스냅샷이 없으면 빈 상태 메시지 표시
- 갱신 정책:
  - 스냅샷 있음: 약 `60s`
  - 스냅샷 없음: 약 `10s`

### 메뉴바

- 제목에 요약 상태 표시(잔여%, 유료 5h 잔여, 갱신 경과)
- 펼침 메뉴에 활성 계정/리셋 시각/갱신 경과 표시
- 약 15초 주기 자동 갱신 + 수동 갱신 지원

## 인증 및 계정 가져오기

### 로컬 탐색 경로

다음 auth JSON 경로를 탐색합니다.

- `~/.codex/auth.json`
- `~/.config/codex/auth.json`
- `~/.openai/auth.json`

### Public OAuth client

기본적으로 public client 플로우를 지원하며, 사용자 OAuth client 파라미터도 사용 가능합니다.

### 수동 callback 플로우

브라우저 callback을 앱 내에서 직접 처리하지 못할 때:

1. `Copy URL and Manual sign in` 클릭
2. 브라우저 로그인 완료
3. callback URL을 입력 필드에 붙여넣기
4. `Import` 클릭

## 워크스페이스

### Authentication

- OAuth 로그인 패널
- Advanced OAuth parameters
- 로컬 OAuth 계정 스캔/가져오기

### Runtime Strategy

- 모드 선택 (`Intelligent`, `Manual`, `Focus`)
- 지능형 전환 임계값
- 저사용량 알림 임계값
- 추천 계정 패널

### Schedule

- 관리 계정 리셋 타임라인 개요
- 일간/주간 사용량 분석 요약
- 커버리지 갭 힌트로 계정 사용 계획 지원
- 계정별 추세선 및 임계값/이상 이벤트
- 분석 데이터 내보내기 (`Copy JSON`, `Export CSV`, `Export JSON`)

### OpenAI Reset Alert

- 유료 계정 리셋 목표 추적
- 조기 리셋 허용 오차 설정
- 조기 리셋 신호 요약/기록
- 데스크톱 알림 및 이벤트 목록 관리

### Settings

- 실행 동작
- 자동 동기화 토글/주기
- 언어
- 외관(system/dark/light)

### Safety

- 백업/내보내기/가져오기 제어
- raw 데이터/로그 진단 패널

## 설치

### 옵션 A: Releases에서 사전 빌드 DMG 다운로드

두 아키텍처용 DMG 제공:

- `CodexPoolManager-<version>-apple-silicon.dmg`
- `CodexPoolManager-<version>-intel.dmg`

Mac 아키텍처에 맞는 파일을 선택하세요.

### 옵션 B: Xcode에서 소스 실행

다음 섹션을 참고하세요.

## 소스에서 빌드

### 요구 사항

- macOS
- Xcode 16+

### 단계

```bash
cd /path/to/AIAgentPool
open CodexPoolManager.xcodeproj
```

Xcode에서:

1. `CodexPoolManager` scheme 선택
2. 로컬 Mac destination 선택
3. Build and Run

Widget 테스트가 필요하면 관련 target의 Team 서명을 동일하게 맞추세요.

## Release DMG 파이프라인

자동 DMG 패키징 + notarization 설정:

- `.github/workflows/release-dmg.yml`
- `scripts/build_and_notarize_dmg.sh`

### 파이프라인 하이라이트

- `arm64`, `x86_64` 모두 빌드
- 아티팩트 이름에 release version/tag 사용 (hash 미사용)
- Developer ID Application 인증서로 서명
- 각 DMG notarize + staple 수행
- workflow artifacts + GitHub Release assets 업로드

### 필요한 GitHub Secrets

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_BASE64`

자세한 설정은 [RELEASE_DMG.md](RELEASE_DMG.md)를 참고하세요.

## 프로젝트 구조

```text
AIAgentPool/
├─ CodexPoolManager/                 # 메인 macOS 앱 target
├─ CodexPoolWidget/                  # Widget extension target
├─ CodexPoolWidgetHost/              # Widget 브리지/테스트 host
├─ Domain/Pool/                      # 코어 상태, 전환 규칙, 스냅샷 모델
├─ Features/PoolDashboard/           # UI + 플로우 코디네이터
├─ Infrastructure/Auth/              # OAuth, auth 파일 접근/전환 서비스
├─ Infrastructure/Usage/             # 사용량 동기화 client/service
├─ CodexPoolManagerTests/            # 단위 테스트
├─ CodexPoolManagerUITests/          # UI 테스트
├─ .github/workflows/release-dmg.yml # Release workflow
└─ scripts/build_and_notarize_dmg.sh # 로컬/CI DMG 스크립트
```

## 테스트

Xcode 또는 명령줄로 실행할 수 있습니다.

```bash
xcodebuild \
  -project CodexPoolManager.xcodeproj \
  -scheme CodexPoolManager \
  -destination 'platform=macOS' \
  test
```

## 문제 해결

### “Syncing...” 상태가 멈춤

- 네트워크/API 가용성 확인
- Sync Error 상세 확인
- token/account id 유효성 확인
- 잠시 후 수동 동기화 재시도

### Widget에 “No snapshot available” 표시

- CodexPoolManager를 한 번 실행(메인 앱이 widget bridge 게시)
- 몇 초 후 Widget 새로고침
- localhost loopback이 방화벽/네트워크 규칙에 막히지 않았는지 확인

### 로컬 OAuth 스캔 결과 없음

- `Choose auth.json`으로 수동 권한 부여
- 알려진 경로 중 하나에 auth 데이터가 있는지 확인

### Intelligent 모드에서 전환되지 않음

- 현재 잔여가 전환 임계값보다 낮은지 확인
- 쿨다운 간격 확인
- 후보 계정 자격/잔여 값 확인
- Focus 모드에서는 자동 전환이 비활성화됨

## 보안 및 개인정보

- Refetchable export에는 민감 정보가 포함될 수 있습니다.
- 마스킹 전 raw 로그/내보내기 파일을 공개 공유하지 마세요.
- 내부 스냅샷은 안전한 저장소를 사용하세요.
- OAuth/client 자격 증명은 보안 정책에 따라 관리하세요.

## 기여

Issue와 PR을 환영합니다.

권장 PR 범위:
- 한 PR에 하나의 동작 변경
- Domain/coordinator 로직 변경 시 테스트 포함
- UI 변경 시 before/after 스크린샷 첨부

---

프로젝트가 도움이 되었다면 Star 부탁드립니다.
