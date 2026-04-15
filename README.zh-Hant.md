# Codex Pool Manager

Codex Pool Manager 是一款 macOS 工具，讓你在同一個控制面板中管理一組 Codex/OpenAI OAuth 帳號。

它可以幫你：
- 追蹤每個帳號的配額與剩餘用量，
- 快速切換目前啟用帳號，
- 依照智慧策略自動輪替帳號，
- 透過桌面 Widget 與選單列掌握狀態，
- 以備份/匯出流程做復原。

語言： [English](README.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## 目錄

1. [截圖](#截圖)
2. [主要功能](#主要功能)
3. [智慧切換運作方式](#智慧切換運作方式)
4. [Widget + 選單列](#widget--選單列)
5. [驗證與帳號匯入](#驗證與帳號匯入)
6. [工作區](#工作區)
7. [安裝](#安裝)
8. [從原始碼建置](#從原始碼建置)
9. [Release DMG 流程](#release-dmg-流程)
10. [專案結構](#專案結構)
11. [測試](#測試)
12. [疑難排解](#疑難排解)
13. [安全與隱私說明](#安全與隱私說明)
14. [貢獻](#貢獻)

## 截圖

以下截圖皆使用 mock 或非敏感測試資料。

### App Icon（目前版本）

![App Icon](docs/images/app-icon.png)

### 主儀表板（深色，Mock 資料）

![Main Dashboard (Dark, Mock Data)](docs/images/app-screenshot.png)

### 頂部總覽（淺色，Mock 資料）

![Header Overview (Light, Mock Data)](docs/images/dashboard-light.png)

### 選單列狀態（Mock 資料）

![Menu Bar Status](docs/images/menu-bar.png)

### Widget（空狀態範例，Mock 狀態）

![Widget Empty State](docs/images/widget-empty-state.png)

### OpenAI Reset Alert（Mock 資料）

![OpenAI Reset Alert](docs/images/openai-reset-alert.png)

## 主要功能

### 1) 帳號池管理

- 新增、編輯、複製與移除帳號。
- 群組管理（`新增`、`重新命名`、`刪除`）。
- 刪除群組時會一併刪除該群組帳號。
- 提供排序與版面配置，便於管理大型帳號池。
- 池統計（`Accounts`、`Available`、`Pool Usage`）具備去重邏輯，避免重複身分被重複計算。

### 2) 多種切換模式

- `Intelligent`：依剩餘容量與策略門檻，自動選擇最佳帳號。
- `Manual`：固定使用你手動選擇的帳號。
- `Focus`：鎖定目前帳號，不進行智慧輪替。

### 3) 用量同步與診斷

- 對所有符合條件的帳號同步 Codex/OpenAI 用量。
- 處理同步排除情況（缺 token、缺 account id、API/網路錯誤）。
- 顯示上次成功同步時間與同步錯誤訊息。
- 提供原始用量 JSON 與切換日誌方便診斷。

### 4) OAuth 登入流程

- App 內 OAuth 登入並直接匯入。
- 手動流程：複製授權 URL、貼上 callback URL、再匯入。
- 可掃描常見本機路徑中的 auth 資料。
- 可將本機 OAuth sessions/accounts 匯入帳號池。

### 5) 桌面整合

- 支援 macOS 原生通知（同步失敗/恢復、低用量、自動切換結果）。
- 提供顯示即時剩餘資訊的選單列工具。
- 提供 macOS Widget 快速檢視狀態。

### 6) 備份與還原

- 匯出 JSON 快照。
- 匯出可重新抓取快照（敏感，含重新抓取所需欄位）。
- 匯入 JSON 快照做遷移/復原。

### 7) 介面與多語

- 深色模式 + 淺色模式。
- 可在設定中切換語言。
- App/Widget 時間文字採用語系格式化。

### 8) 用量分析與 Schedule 規劃

- 提供獨立 `Schedule` 工作區規劃多帳號重置時程。
- 提供每日/每週用量分析，辨識使用習慣。
- 顯示覆蓋/未覆蓋時段，提早發現可能無帳號可用的空窗。
- 提供單一帳號趨勢線、門檻事件與異常摘要。
- 支援匯出分析資料（JSON/CSV）供後續分析。

### 9) OpenAI 重置監測

- 提供獨立的 `OpenAI Reset Alert` 工作區監測付費帳號重置。
- 同時監測週重置與 5 小時重置目標。
- 當重置時間早於預期（在容差範圍內）時標記為提前重置訊號。
- 支援桌面通知與事件歷史紀錄。

## 智慧切換運作方式

此段描述執行期實際行為，方便使用者了解切換時機。

### 帳號資格

只有**未被排除同步/排程**的帳號會納入自動切換候選。

常見排除原因：
- 缺少 API token，
- 缺少 ChatGPT account id，
- 同步錯誤狀態。

### 付費/非付費剩餘邏輯

- 非付費帳號：以週剩餘比例（`remainingUnits / quota`）判斷。
- 付費帳號（預設）：以 **5 小時剩餘** 百分比為主要判斷。
- 付費帳號特殊情況：若週剩餘已是 `0%`，則以週剩餘為準（視為已耗盡）。

### 候選選擇

系統會在可用候選中選擇智慧剩餘比例最高者。

週剩餘 `<= 0` 的帳號不會被選為候選。

### 觸發切換條件

`Intelligent` 模式下，需同時滿足以下條件才會切換：

1. 有有效候選；
2. 目前帳號低於智慧切換門檻；
3. 候選優於目前帳號；
4. 已超過冷卻間隔。

### Focus 模式行為

切入 `Focus` 後，會鎖定目前帳號避免意外跳號。

Focus 模式不進行智慧自動切換。

### 低用量提醒門檻是獨立設定

有兩個不同門檻：

- 智慧切換門檻：控制**何時允許切換**。
- 低剩餘提醒門檻：控制**何時顯示警示/通知**。

兩者彼此獨立。

## Widget + 選單列

### Widget

- Widget 透過主程式提供的本機橋接快照讀取資料。
- 若無快照，Widget 會顯示友善空狀態提示。
- 時間線更新策略：
  - 有快照時約每 `60s` 更新，
  - 無快照時約每 `10s` 更新。

### 選單列

- 選單列標題顯示精簡狀態（剩餘%、付費 5h 剩餘、更新時間）。
- 展開內容顯示目前帳號、重置時間與更新年齡。
- 週期性刷新（約每 15 秒）並支援手動刷新。

## 驗證與帳號匯入

### 本機帳號掃描路徑

會掃描以下常見 auth JSON 路徑：

- `~/.codex/auth.json`
- `~/.config/codex/auth.json`
- `~/.openai/auth.json`

### 公開 OAuth Client

預設支援公開 client 流程，也可改用你自己的 OAuth client 參數。

### 手動 callback 流程

若瀏覽器 callback 無法在 App 內直接完成：

1. 點 `Copy URL and Manual sign in`；
2. 在瀏覽器完成登入；
3. 將 callback URL 貼回欄位；
4. 點 `Import`。

## 工作區

介面以工作區分工，讓操作邊界更清楚。

### Authentication

- OAuth 登入面板
- 進階 OAuth 參數
- 本機 OAuth 帳號掃描/匯入

### Runtime Strategy

- 模式選擇（`Intelligent`、`Manual`、`Focus`）
- 智慧切換門檻
- 低剩餘提醒門檻
- 智慧建議面板

### Schedule

- 管理帳號的重置時間軸總覽
- 每日/每週用量分析摘要
- 覆蓋缺口提示，協助規劃帳號使用
- 單一帳號趨勢線與門檻/異常事件
- 分析資料匯出（`Copy JSON`、`Export CSV`、`Export JSON`）

### OpenAI Reset Alert

- 付費帳號重置目標追蹤
- 提前重置容差設定
- 提前重置訊號摘要與紀錄
- 桌面提醒與事件清單管理

### Settings

- 啟動行為
- 自動同步開關與間隔
- 語言
- 外觀（system/dark/light）

### Safety

- 備份/匯出/匯入控制
- 原始資料/日誌檢視的診斷區塊

## 安裝

### 方式 A：從 Releases 下載預建 DMG

Release 提供兩種架構 DMG：

- `CodexPoolManager-<version>-apple-silicon.dmg`
- `CodexPoolManager-<version>-intel.dmg`

請下載符合你 Mac 架構的版本。

### 方式 B：在 Xcode 從原始碼執行

見下節。

## 從原始碼建置

### 需求

- macOS
- Xcode 16+

### 步驟

```bash
cd /path/to/AIAgentPool
open CodexPoolManager.xcodeproj
```

在 Xcode：

1. 選擇 `CodexPoolManager` scheme。
2. 選擇本機 Mac 作為 destination。
3. Build and Run。

若要測 Widget，請確保相關 target 使用同一組簽章 Team。

## Release DMG 流程

自動 DMG 打包與 notarization 位置：

- `.github/workflows/release-dmg.yml`
- `scripts/build_and_notarize_dmg.sh`

### 流程重點

- 同時建置 `arm64` 與 `x86_64`。
- 產物命名使用 release 版號/tag（非 commit hash）。
- 使用 Developer ID Application 憑證簽章。
- 對每個 DMG 進行 notarize 與 staple。
- 上傳到 workflow artifacts 與 GitHub Release assets。

### 必要 GitHub Secrets

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_BASE64`

詳細設定請見 [RELEASE_DMG.md](RELEASE_DMG.md)。

## 專案結構

```text
AIAgentPool/
├─ CodexPoolManager/                 # 主 macOS App target
├─ CodexPoolWidget/                  # Widget extension target
├─ CodexPoolWidgetHost/              # Widget 橋接/測試用 companion host
├─ Domain/Pool/                      # 核心狀態、切換規則、快照模型
├─ Features/PoolDashboard/           # UI 與流程協調器
├─ Infrastructure/Auth/              # OAuth、auth 檔存取/切換服務
├─ Infrastructure/Usage/             # 用量同步 client/service
├─ CodexPoolManagerTests/            # 單元測試
├─ CodexPoolManagerUITests/          # UI 測試
├─ .github/workflows/release-dmg.yml # Release workflow
└─ scripts/build_and_notarize_dmg.sh # 本機/CI DMG 腳本
```

## 測試

可在 Xcode 執行，或使用命令列：

```bash
xcodebuild \
  -project CodexPoolManager.xcodeproj \
  -scheme CodexPoolManager \
  -destination 'platform=macOS' \
  test
```

## 疑難排解

### 「Syncing...」卡住

- 先確認網路/API 是否可用。
- 檢查 Sync Error 提示內容。
- 確認帳號有有效 token 與 account id。
- 稍後再手動同步一次。

### Widget 顯示「No snapshot available」

- 先開啟一次 CodexPoolManager（主程式會發佈 widget bridge）。
- 等幾秒後刷新 Widget。
- 確認本機防火牆/網路規則未阻擋 localhost loopback。

### 本機 OAuth 掃描不到資料

- 改用 `Choose auth.json` 手動授權。
- 確認 auth 檔存在於已知路徑之一。

### Intelligent 模式未切換

- 檢查目前剩餘是否低於切換門檻。
- 檢查冷卻間隔。
- 檢查候選帳號資格與剩餘值。
- Focus 模式下本來就不會智慧切換。

## 安全與隱私說明

- 可重新抓取匯出可能包含敏感資料。
- 未去識別化前，請勿公開分享原始日誌或匯出內容。
- 內部快照請使用安全儲存。
- OAuth/client 憑證請依你的安全政策管理。

## 貢獻

歡迎提出 Issue 與 PR。

建議 PR 範圍：
- 每個 PR 聚焦單一行為變更，
- Domain 或 coordinator 邏輯要有對應測試，
- UI 變更附上前後截圖。

---

如果這個專案有幫助到你的 Codex 帳號管理，歡迎幫 repo 加星。
