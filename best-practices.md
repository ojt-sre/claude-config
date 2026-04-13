# best-practices — 全リポジトリ共通のベストプラクティス

> **ここに書くもの**: 実運用から得た設計上の判断基準・非自明な挙動・経験則（知見）。
> **書かないもの**: 守るべき規約 → `coding-standards.md` / 具体的な失敗コマンド → `known-failures.md`
> `/promote` コマンドで各リポジトリから昇格された汎用的な知見を蓄積する。
> 最終更新: 2026-04-14

---

## Claude Code 運用

- `claude --print` サブプロセスでは `settings.json` の `permissions.allow` が `--allowed-tools` より優先される。Write を制限するには `settings.json` から外し、hook で対話セッションのみ自動承認する
- frontmatter の `model:` でコマンドごとに最適なモデルを指定できる。L3 判断は Sonnet 以上、単純パースは Haiku で十分
- cron 環境では NVM が未ロード。スクリプト冒頭で明示的に `source "$NVM_DIR/nvm.sh"` する

## SRE / インフラ

- Terraform の `prevent_destroy` はリソース定義に付ける。モジュール外から上書きできない
- ECS タスク定義の変更は `force_new_deployment = true` を忘れると反映されない
- IAM ポリシーは最小権限 + 条件キー（`aws:SourceIp` 等）で絞る

