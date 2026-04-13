# claude-config — Claude Code グローバル設定（V3）

SREエンジニア16年の実務経験をベースに設計した、Claude Code（`~/.claude/`）のグローバル設定一式。

V2（「場当たりルールからの設計」）→ V3（「自律的に進化する仕組み」）への進化記録でもある。

## 設計思想

- **AI = 高価なCPU** — 検索・計算・パース等のトイルはPython/Shell/MCPに委任。AIには判断と創造だけやらせる
- **コンテキストは負債** — 設定ファイルもセッション状態もトークンを消費する。最小限に保つ
- **5層アーキテクチャ** — L5(Meta) → L4(Validation) → L3(Creative) → L2(Skill) → L1(Infra) の責務分離

### V3 で追加された設計要素

- **architecture.md** — 機能→アーティファクト対応表。機能廃止時に全関連ファイルを漏れなく削除するための仕組み
- **情報収集パイプライン** — 技術フィード（L1）とセキュリティトリアージ（L1→L3）を分離。収集と判断を混在させない
- **L5 自律権限** — ルール追記・health-check 拡張・メモリ整理をユーザー確認なしで実行できる standing permission
- **コンテキスト分離原則** — 同じデータでも関心事が異なれば別サービスにする

## ファイル構成

```
~/.claude/
├── CLAUDE.md                  # V3 設計憲法（コア設定）
├── coding-standards.md        # コーディング規約（全プロジェクト共通）
├── known-failures.md          # コマンド失敗パターン集
├── best-practices.md          # 汎用ベストプラクティス集
├── architecture.md            # 機能→アーティファクト対応表
│
├── agents/                    # サブエージェント定義
│   ├── cost-optimizer.md      #   AWS コスト最適化
│   ├── security-auditor.md    #   セキュリティ監査
│   └── terraform-reviewer.md  #   Terraform コードレビュー
│
├── commands/                  # スラッシュコマンド
│   ├── confirm.md             #   /confirm — リポジトリ健全性チェック
│   ├── learn.md               #   /learn — ナレッジ保存
│   ├── new-repo.md            #   /new-repo — 新規リポジトリセットアップ
│   ├── optimize-global.md     #   /optimize-global — グローバル設定最適化
│   ├── post-mortem.md         #   /post-mortem — ポストモーテム作成
│   ├── promote.md             #   /promote — ローカル知見のグローバル昇格
│   ├── runbook-template.md    #   /runbook-template — Runbook作成
│   ├── security-triage.md     #   セキュリティトリアージ（cron）
│   └── weekly-review.md       #   /weekly-review — 週次レビュー
│
├── config/                    # 設定ファイル
│   └── tech-feeds.json        #   技術フィード購読リスト
│
├── hooks/                     # イベントフック
│   ├── session-start.sh       #   セッション開始時の引き継ぎ・リマインド
│   ├── stop-hook.sh           #   セッション終了時の通知
│   ├── validate-command.sh    #   危険コマンドのブロック
│   ├── auto-approve-bash.sh   #   安全なBashコマンドの自動承認
│   ├── auto-approve-edit-write.sh  # Edit/Write の自動承認
│   ├── log-bash-approval.sh   #   承認パターンの学習記録
│   ├── log-bash-failure.sh    #   失敗パターンの記録
│   └── post-tool-use.sh       #   .tf 編集後の terraform fmt 自動実行
│
├── scripts/                   # L1/L4 ツール
│   ├── lib.sh                 #   共通ライブラリ（run_cmd / dispatch_ops）
│   ├── health-check.py        #   リポジトリ健全性チェック（L4）
│   ├── cost-report.py         #   トークンコスト集計・予算チェック
│   ├── lint-ai-style.py       #   AI臭い表現のスコアリング
│   ├── fetch-tech-feeds.py    #   RSS/Atom/GitHub Advisory 統合取得（L1）
│   ├── daily-tech-feeds.sh    #   技術フィード収集 cron（毎日6時）
│   └── daily-security-triage.sh  # セキュリティトリアージ cron（毎日7時）
│
├── templates/                 # 新規リポジトリ用テンプレート
│   ├── base/                  #   汎用テンプレート
│   └── sre/                   #   SRE向けテンプレート
│
├── settings.example.json      # settings.json のサンプル（hooks 配線）
├── statusline.py              # ステータスライン表示
└── LICENSE                    # MIT License
```

## 使い方

1. このリポジトリの構成を参考に、自分の `~/.claude/` を組み立てる
2. `settings.example.json` を `settings.json` にコピーし、環境に合わせて編集する
3. `CLAUDE.md` の口調設定・リポジトリ定義を自分用にカスタマイズする
4. `health-check.py` の REPOS にチェック対象リポジトリを追加する

## 特徴

### architecture.md パターン
各リポジトリに「機能→アーティファクト対応表」を作り、ACTIVE / NOT STARTED / DISCONTINUED のステータスを付ける。機能廃止時に関連ファイルを漏れなく削除でき、health-check.py がその整合性を自動検証する。

### 情報収集パイプライン
技術フィード（`daily-tech-feeds.sh`）とセキュリティトリアージ（`daily-security-triage.sh`）を分離。収集（L1）と判断（L3）を混在させないコンテキスト分離原則に基づく設計。

### hooks による自動化
- セッション開始時に前回の引き継ぎメモと未完了タスクを自動表示
- 危険なコマンド（`git push --force`、`npm install -g` 等）を自動ブロック
- 安全なBashコマンドパターンを学習して自動承認

### lint-ai-style.py
AI生成テキストにありがちな表現（「〜を確保する」「包括的な」等）をスコアリングし、人間らしい文章に近づける。

### statusline.py
Claude Code のステータスラインにコンテキスト使用率・レートリミット残量をグラデーションバーで表示する。`settings.json` の `statusLine` に設定して使う。

## 環境

- WSL2 (Ubuntu) 上で運用
- Git: WSL側の git を使用（HTTPS）
- Node.js: NVM経由

## 関連記事

- [Claude Code × Terraform — 本番事故を防ぐ3つのガードレール設計](https://zenn.dev/ojt/articles/claude-code-terraform-guardrails)
- [Claude Code で terraform plan を解析する — apply前に危険を見逃さない4パターン](https://zenn.dev/ojt/articles/2026-03-30-terraform-plan-claude-prompt-patterns)
- [Claude Code を使いこなす CLAUDE.md 設計 — ルールが増えても崩れない体系の作り方](https://zenn.dev/ojt/articles/2026-04-01-claude-code-v2-constitution)

## ライセンス

MIT
