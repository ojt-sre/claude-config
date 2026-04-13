---
description: 全リポジトリを横断して知見を吸い上げ、グローバル設定を最適化する
---

全リポジトリの設定を横断的に分析し、グローバル設定への昇格・重複排除・未整備リポジトリへの展開を行います。

## 対象リポジトリ

- `~/.claude/` （グローバル）
- `~/my-freelance-sre/`
- `~/content-pipeline/`
- `~/lol-guides-jp/`
- `~/zenn-content/`

## 手順

### Phase 1: 現状分析
各リポジトリの以下のファイルを読み込む:
- `CLAUDE.md` / `.clauderules` / `.claudeignore`
- `.claude/agents/` と `.claude/commands/` の一覧
- `known-failures.md`（あれば）
- `MyBestPractices.md`（あれば）

### Phase 2: 共通パターンの抽出
- 複数リポジトリで重複している記述を特定する
- グローバルに昇格すべき汎用ルール・知見を列挙する

### Phase 3: グローバル昇格（追記のみ）
- 抽出した共通ルールを `~/.claude/CLAUDE.md` に追記する
- 失敗パターンは `~/.claude/known-failures.md` に追記する
- `~/.claude/CLAUDE.md` は500字以内を維持する

### Phase 4: 未整備リポジトリへの展開
以下が不足しているリポジトリには最小構成を作成する:
- `CLAUDE.md`（なければ作成）
- `.clauderules`（なければ作成）

### Phase 5: レポート出力
以下の形式で結果を報告する:

```
## 全体最適化レポート

### グローバルに昇格した内容
- ...

### 未整備リポジトリへの展開
- ...

### 重複として検出した項目（要手動確認）
- ...

### 対応不要（リポジトリ固有）
- ...
```

## 制約

- cron で動いているスクリプトが参照するファイルは削除・移動しない
  - `content-pipeline/.claude/commands/` 配下（daily-produce.sh 等が参照）
  - `lol-guides-jp/.claude/commands/` 配下（daily-guide.sh が参照）
- 既存の記述を勝手に削除しない（追記・提案のみ）
- 削除が必要な重複はレポートに記載し、実行はユーザーの確認後にする
