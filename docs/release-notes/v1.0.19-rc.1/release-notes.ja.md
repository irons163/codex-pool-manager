# CodexPoolManager v1.0.19-rc.1

リリース日：2026-08-28

## 修正

- アカウント切り替え時に、資格情報を書き換える前に Codex を終了し、実行中のセッションが取り消されたと判定されないようにしました。
- 切り替え時に対象アカウントの refresh/id トークンを書き込み、前のアカウントのトークンを残さないようにしました。
- Codex の Keychain と、新しい Codex が使う `current_account` ミラーも更新します。

## Prerelease の注記

- この prerelease では、Codex 更新後のアカウント切り替えを正式版公開前に検証します。
