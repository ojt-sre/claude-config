# グローバルスコープ アーキテクチャ対応表

> `~/.claude/` 配下のグローバルアーティファクト。各リポジトリ共通の基盤機能。
> 最終更新: 2026-04-13

---

## 機能一覧

### 技術フィード収集（ACTIVE）

毎日6時に RSS/Atom/Scrape でフィードを取得し、CLAUDE.local.md にサマリを記録する。L1のみ。

| 種別 | パス |
|---|---|
| script | `scripts/daily-tech-feeds.sh` |
| script | `scripts/fetch-tech-feeds.py` |
| config | `config/tech-feeds.json` |
| config | `config/discord.env` |
| cron | `0 6 * * *` daily-tech-feeds.sh |
| output | `reports/tech-feeds-latest.json` |

### セキュリティトリアージ（ACTIVE）

毎日7時に GitHub Advisory (critical) を取得し、L3 Sonnet でトリアージ後、CLAUDE.local.md に通知する。

| 種別 | パス |
|---|---|
| script | `scripts/daily-security-triage.sh` |
| script | `scripts/fetch-tech-feeds.py`（共用） |
| command | `commands/security-triage.md` |
| cron | `0 7 * * *` daily-security-triage.sh |
| output | `reports/security-advisories-latest.json` |
| output | `reports/security-triage-latest.json` |

### ヘルスチェック（ACTIVE）

全リポジトリの設定・スクリプト・メモリの整合性を検証する。weekly-review から呼ばれる。

| 種別 | パス |
|---|---|
| script | `scripts/health-check.py` |
| output | `reports/health-check-latest.txt` |

### コスト分析（ACTIVE）

API 使用量のレポートを生成する。

| 種別 | パス |
|---|---|
| script | `scripts/cost-report.py` |

### AI文体チェック（ACTIVE）

AI 生成コンテンツの文体を検証する。

| 種別 | パス |
|---|---|
| script | `scripts/lint-ai-style.py` |

### 共通ライブラリ（ACTIVE）

`run_cmd()` 等の共通関数。各リポジトリの `scripts/lib.sh` から委譲される canonical 版。

| 種別 | パス |
|---|---|
| script | `scripts/lib.sh` |

### Hook 基盤（ACTIVE）

Claude Code のツール実行を制御する hook 群。

| 種別 | パス |
|---|---|
| hook | `hooks/auto-approve-bash.sh` |
| hook | `hooks/auto-approve-edit-write.sh` |
| hook | `hooks/log-bash-approval.sh` |
| hook | `hooks/log-bash-failure.sh` |
| hook | `hooks/post-tool-use.sh` |
| hook | `hooks/session-start.sh` |
| hook | `hooks/validate-command.sh` |

### 対話コマンド（ACTIVE）

ユーザーまたはスクリプトから呼び出される L3 プロンプト。

| 種別 | パス | 用途 |
|---|---|---|
| command | `commands/confirm.md` | リポジトリ健全性チェック |
| command | `commands/learn.md` | セッションの学びを保存 |
| command | `commands/new-repo.md` | 新規リポジトリ作成 |
| command | `commands/optimize-global.md` | 全リポジトリ横断の最適化 |
| command | `commands/post-mortem.md` | SRE ポストモーテム作成 |
| command | `commands/promote.md` | 知見のグローバル昇格 |
| command | `commands/runbook-template.md` | SRE Runbook 生成 |
| command | `commands/rank-tech-feeds.md` | テックフィードのランキング・要約 |
| command | `commands/security-triage.md` | セキュリティトリアージ（run_cmd用） |
| command | `commands/weekly-review.md` | 週次レビュー |

### サブエージェント（ACTIVE）

特化型のレビュー・監査エージェント。`Agent` ツールの `subagent_type` で呼び出される。

| 種別 | パス | 用途 |
|---|---|---|
| agent | `agents/cost-optimizer.md` | AWS コスト最適化分析 |
| agent | `agents/security-auditor.md` | セキュリティ監査 |
| agent | `agents/terraform-reviewer.md` | Terraform コードレビュー |

### テンプレート（ACTIVE）

`/new-repo` コマンドで使用するリポジトリ初期化テンプレート。

| 種別 | パス | 用途 |
|---|---|---|
| template | `templates/base/CLAUDE.local.md` | 汎用: ローカル設定テンプレート |
| template | `templates/base/.claudeignore` | 汎用: 無視ファイル設定 |
| template | `templates/base/.clauderules` | 汎用: ルール定義 |
| template | `templates/base/.gitignore` | 汎用: Git 除外設定 |
| template | `templates/base/CLAUDE.md` | 汎用: プロジェクト憲法 |
| template | `templates/base/README.md` | 汎用: README |
| template | `templates/sre/CLAUDE.md` | SRE: プロジェクト憲法 |
| template | `templates/sre/.claudeignore` | SRE: 無視ファイル設定 |
| template | `templates/sre/.clauderules` | SRE: Terraform/Python ルール |

### ステータスライン（ACTIVE）

Claude Code のステータスラインにカスタム情報を表示する。

| 種別 | パス |
|---|---|
| script | `statusline.py` |

### コア設定・ドキュメント（ACTIVE）

リポジトリ自身の設定・規約・リファレンス。

| 種別 | パス | 用途 |
|---|---|---|
| config | `CLAUDE.md` | V3 設計憲法 |
| config | `coding-standards.md` | コーディング規約 |
| config | `known-failures.md` | コマンド失敗パターン集 |
| config | `best-practices.md` | 汎用ベストプラクティス |
| config | `architecture.md` | 機能→アーティファクト対応表 |
| config | `settings.example.json` | settings.json のサンプル |
| doc | `README.md` | リポジトリ説明 |
| doc | `LICENSE` | MIT ライセンス |
| config | `.gitignore` | Git 除外設定 |
