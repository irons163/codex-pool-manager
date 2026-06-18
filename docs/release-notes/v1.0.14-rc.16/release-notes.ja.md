# CodexPoolManager v1.0.14-rc.16

リリース日：2026-06-18

## 修正

- OAuth ChatGPT アカウントで refresh token、ID token、最終更新時刻を token vault に保持するようにしました。
- 使用量同期で 401/403 が返った場合、OAuth access token を更新してから 1 回だけ再試行します。
- ローカルの auth.json 取り込み時に、refresh token と ID token も管理対象の OAuth アカウントへ引き継ぎます。
- 同期結果のマージ時に、古い同期スナップショットでローカルの新しい認証情報を上書きしないようにしました。

## 注意事項

- この prerelease は、stable 公開前に OAuth アカウントの自動更新安定性を検証するためのものです。
- リレー API key、config.toml、auth.json の移行は不要です。
