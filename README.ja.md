# Codex Pool Manager

Codex Pool Manager は、Codex/OpenAI OAuth アカウントのプールを 1 つのコントロールパネルで運用するための macOS アプリです。

主な用途：
- アカウントごとのクォータと残量の追跡
- アクティブ認証アカウントの高速切り替え
- インテリジェントポリシーによる自動ローテーション
- デスクトップ Widget とメニューバーでの状態監視
- バックアップ/エクスポートによる復旧

言語: [English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## 目次

1. [スクリーンショット](#スクリーンショット)
2. [主要機能](#主要機能)
3. [インテリジェント切り替えの仕組み](#インテリジェント切り替えの仕組み)
4. [Widget + メニューバー](#widget--メニューバー)
5. [認証とアカウント取り込み](#認証とアカウント取り込み)
6. [ワークスペース](#ワークスペース)
7. [インストール](#インストール)
8. [ソースからビルド](#ソースからビルド)
9. [Release DMG パイプライン](#release-dmg-パイプライン)
10. [プロジェクト構成](#プロジェクト構成)
11. [テスト](#テスト)
12. [トラブルシューティング](#トラブルシューティング)
13. [セキュリティとプライバシー](#セキュリティとプライバシー)
14. [コントリビュート](#コントリビュート)

## スクリーンショット

以下は mock または非機密のテストデータです。

### App Icon（現行版）

![App Icon](docs/images/app-icon.png)

### メインダッシュボード（Dark / Mock）

![Main Dashboard (Dark, Mock Data)](docs/images/app-screenshot.png)

### ヘッダー概要（Light / Mock）

![Header Overview (Light, Mock Data)](docs/images/dashboard-light.png)

### メニューバー表示（Mock）

![Menu Bar Status](docs/images/menu-bar.png)

### Widget（空状態サンプル / Mock）

![Widget Empty State](docs/images/widget-empty-state.png)

### OpenAI Reset Alert（Mock）

![OpenAI Reset Alert](docs/images/openai-reset-alert.png)

## 主要機能

### 1) アカウントプール管理

- アカウントの追加・編集・複製・削除。
- グループ管理（`Add`、`Rename`、`Delete`）。
- グループ削除時は、そのグループのアカウントも削除。
- 大規模プール向けに並び替えとレイアウト切替を提供。
- `Accounts` / `Available` / `Pool Usage` は重複 ID を考慮して集計。

### 2) 複数の切り替えモード

- `Intelligent`: 残量とポリシー閾値に基づき最適アカウントを自動選択。
- `Manual`: 手動で選んだアカウントを維持。
- `Focus`: 現在アカウントを固定し、自動ローテーションを無効化。

### 3) 使用量同期と診断

- 対象アカウントの Codex/OpenAI 使用量を同期。
- 同期除外（token 不足、account id 不足、API/ネットワークエラー）を処理。
- 最終成功同期時刻とエラー詳細を表示。
- 診断用に raw usage JSON と switch log を表示。

### 4) OAuth サインインフロー

- アプリ内 OAuth サインイン + 直接取り込み。
- 手動フロー（認可 URL コピー → callback URL 貼り付け → 取り込み）。
- 一般的なローカルパスから auth データを探索。
- ローカル OAuth sessions/accounts を管理プールへ取り込み。

### 5) デスクトップ連携

- macOS 通知（同期失敗/復帰、低残量、自動切り替え結果）。
- 残量要約を表示するメニューバーエクストラ。
- 状態確認用の macOS Widget。

### 6) バックアップと復元

- JSON スナップショットのエクスポート。
- 再取得用スナップショットのエクスポート（機微情報を含む可能性）。
- JSON スナップショットのインポートで移行/復元。

### 7) UI と多言語

- Dark mode + Light mode。
- アプリ設定で言語切替。
- App/Widget の時刻表示はロケール準拠。

### 8) 使用量分析と Schedule 計画

- 複数アカウントのリセット時刻を俯瞰できる `Schedule` ワークスペースを提供。
- 日次/週次の使用量分析で利用パターンを可視化。
- アカウント間のカバレッジ不足時間帯を検出して、空白リスクを把握。
- アカウント別のトレンド線、閾値イベント、異常サマリーを表示。
- 分析データを JSON/CSV でエクスポート可能。

### 9) OpenAI リセット監視

- 有料アカウント向け `OpenAI Reset Alert` ワークスペースを提供。
- 週次リセットと 5 時間リセットを同時監視。
- 想定より早いリセットを検出（設定可能な許容値あり）。
- デスクトップ通知とイベント履歴を提供。

## インテリジェント切り替えの仕組み

実行時の動作を明確に説明します。

### 対象アカウント

**同期/スケジュール除外でない**アカウントのみ自動切り替え候補になります。

除外例：
- API token がない
- ChatGPT account id がない
- 同期エラー状態

### 有料/非有料の残量判定

- 非有料: 週次残量比（`remainingUnits / quota`）で判定。
- 有料（既定）: **5 時間残量**% を主判定に使用。
- 有料の例外: 週次残量が `0%` の場合は週次残量を優先。

### 候補選定

候補の中から、インテリジェント残量比が最大のアカウントを選びます。

週次残量 `<= 0` のアカウントは候補になりません。

### 切り替え発火条件

`Intelligent` では次の条件をすべて満たした場合のみ切り替えます。

1. 有効な候補が存在
2. 現在アカウントが切替閾値を下回る
3. 候補が現在アカウントより良い
4. クールダウンが経過済み

### Focus モード

`Focus` へ入ると現在アカウントを固定し、予期しない変更を防ぎます。

Focus ではインテリジェント自動切り替えは実行されません。

### 低残量アラート閾値は別設定

2 つの閾値は独立です。

- Intelligent switch threshold: **切り替え許可条件**
- Low remaining alert threshold: **警告/通知表示条件**

## Widget + メニューバー

### Widget

- メインアプリが公開するローカル bridge スナップショットを利用。
- スナップショットがない場合は空状態メッセージを表示。
- 更新ポリシー：
  - スナップショットあり: 約 `60s`
  - スナップショットなし: 約 `10s`

### メニューバー

- タイトルに要約（残量%、有料 5h 残量、更新経過）を表示。
- 展開メニューでアクティブアカウント、リセット時刻、更新経過を表示。
- 約 15 秒ごとに更新、手動更新も可能。

## 認証とアカウント取り込み

### ローカル探索パス

次の auth JSON を探索します。

- `~/.codex/auth.json`
- `~/.config/codex/auth.json`
- `~/.openai/auth.json`

### Public OAuth client

既定で public client フローに対応し、独自 OAuth client 設定も利用できます。

### 手動 callback フロー

ブラウザ callback をアプリ内で受け取れない場合：

1. `Copy URL and Manual sign in` をクリック
2. ブラウザでサインイン完了
3. callback URL を入力欄へ貼り付け
4. `Import` をクリック

## ワークスペース

### Authentication

- OAuth サインイン
- Advanced OAuth parameters
- ローカル OAuth account のスキャン/取り込み

### Runtime Strategy

- モード選択（`Intelligent`、`Manual`、`Focus`）
- インテリジェント切替閾値
- 低残量アラート閾値
- 推奨アカウント表示

### Schedule

- 管理アカウントのリセット時刻タイムライン表示
- 日次/週次の使用量分析サマリー
- カバレッジギャップの検出で運用計画を支援
- アカウント別トレンド線と閾値/異常イベント
- 分析データのエクスポート（`Copy JSON`、`Export CSV`、`Export JSON`）

### OpenAI Reset Alert

- 有料アカウントのリセット目標監視
- 早期リセット許容値の設定
- 早期リセットシグナルの要約/履歴
- デスクトップ通知とイベント管理

### Settings

- 起動挙動
- 自動同期 ON/OFF と間隔
- 言語
- 外観（system/dark/light）

### Safety

- バックアップ/エクスポート/インポート
- raw データ/ログの診断表示

## インストール

### 方法 A: Releases から DMG を取得

2 種類のアーキテクチャ向け DMG を提供：

- `CodexPoolManager-<version>-apple-silicon.dmg`
- `CodexPoolManager-<version>-intel.dmg`

Mac のアーキテクチャに合わせて選択してください。

### 方法 B: Xcode でソース実行

次節を参照。

## ソースからビルド

### 要件

- macOS
- Xcode 16+

### 手順

```bash
cd /path/to/AIAgentPool
open CodexPoolManager.xcodeproj
```

Xcode で：

1. `CodexPoolManager` scheme を選択
2. ローカル Mac destination を選択
3. Build and Run

Widget もテストする場合、関連 target の Team 署名を合わせてください。

## Release DMG パイプライン

自動 DMG 生成 + notarization 設定：

- `.github/workflows/release-dmg.yml`
- `scripts/build_and_notarize_dmg.sh`

### ハイライト

- `arm64` と `x86_64` を両方ビルド
- 成果物名に release version/tag を使用（hash 不使用）
- Developer ID Application 証明書で署名
- 各 DMG を notarize + staple
- workflow artifacts と GitHub Release assets の両方へアップロード

### 必要な GitHub Secrets

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_BASE64`

詳細は [RELEASE_DMG.md](RELEASE_DMG.md) を参照してください。

## プロジェクト構成

```text
AIAgentPool/
├─ CodexPoolManager/                 # メイン macOS アプリ target
├─ CodexPoolWidget/                  # Widget extension target
├─ CodexPoolWidgetHost/              # Widget ブリッジ/検証用 host
├─ Domain/Pool/                      # コア状態・切替ルール・スナップショット
├─ Features/PoolDashboard/           # UI + フローコーディネータ
├─ Infrastructure/Auth/              # OAuth・auth ファイルアクセス/切替
├─ Infrastructure/Usage/             # 使用量同期 client/service
├─ CodexPoolManagerTests/            # Unit tests
├─ CodexPoolManagerUITests/          # UI tests
├─ .github/workflows/release-dmg.yml # Release workflow
└─ scripts/build_and_notarize_dmg.sh # ローカル/CI DMG スクリプト
```

## テスト

Xcode から、またはコマンドラインで実行できます。

```bash
xcodebuild \
  -project CodexPoolManager.xcodeproj \
  -scheme CodexPoolManager \
  -destination 'platform=macOS' \
  test
```

## トラブルシューティング

### “Syncing...” が止まる

- ネットワーク/API の可用性を確認
- Sync Error の詳細を確認
- token と account id が有効か確認
- 少し待って手動同期を再実行

### Widget に “No snapshot available” が表示される

- CodexPoolManager を一度起動（widget bridge を公開）
- 数秒待って Widget を更新
- localhost loopback が FW/ネットワーク設定で遮断されていないか確認

### ローカル OAuth スキャンで見つからない

- `Choose auth.json` で手動許可
- 既知パスに auth データがあるか確認

### Intelligent モードで切り替わらない

- 現在残量が閾値を下回っているか確認
- クールダウン間隔を確認
- 候補アカウントの資格と残量を確認
- Focus モードでは自動切替しない仕様

## セキュリティとプライバシー

- Refetchable export には機微情報が含まれる可能性があります。
- マスク前の raw log / export を公開しないでください。
- 内部スナップショットは安全な場所へ保存してください。
- OAuth/client 資格情報は自組織のポリシーに従って管理してください。

## コントリビュート

Issue / PR を歓迎します。

推奨する PR スコープ：
- 1 PR 1 挙動変更
- Domain / coordinator 変更にはテストを追加
- UI 変更には before/after スクリーンショットを添付

---

このプロジェクトが役立ったら、ぜひ Star をお願いします。
