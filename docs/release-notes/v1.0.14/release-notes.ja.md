# CodexPoolManager v1.0.14

リリース日：2026-06-09

## 修正

- リレー API key アカウントへの切り替えで、非同期の切り替え処理に入る前にアカウント、provider、API key のデータをスナップショット化するよう強化しました。v1.0.13 の release 版で確認されたクラッシュを対象にした修正です。
- release 版でリレーアカウントへ切り替える際に残っていたクラッシュ要因を回避しました。非同期ログイン closure 内で API key 文字列を再度 trim せず、準備済みの API key bytes を Codex CLI ログイン処理へ渡します。
- リレー API key フォームの追加可能状態の判定を SwiftUI body の描画処理から外し、画面更新時の不要な文字列 trim を避けるようにしました。

## 注意事項

- アカウント、API key、auth.json、config.toml の移行作業は不要です。
- この prerelease は、stable 公開前にリレー API key 切り替え hotfix を検証するためのものです。
- GitHub Release に対応する dSYM を添付するようになり、release 版 crash の調査とシンボル化されたログの取得に使えます。
