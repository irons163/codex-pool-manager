# CodexPoolManager v1.0.12

リリース日：2026-06-09

## 修正

- v1.0.11 の Release ビルドで、起動後しばらくしてクラッシュする可能性がある問題を修正しました。
- XCTest の設定隔離は維持しつつ、正式版 dashboard の起動経路をより安定した production 経路へ戻しました。
- dashboard coverage helper の debug-only MainActor warning を減らしました。

## 注意事項

- アカウント、API key、auth.json、config.toml の移行作業は不要です。
- v1.0.11 を利用しているすべてのユーザーに、この hotfix への更新をおすすめします。
