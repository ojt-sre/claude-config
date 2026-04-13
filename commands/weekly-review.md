---
description: 週次ベストプラクティス更新と全体確認
---

# /weekly-review — 週次ベストプラクティス更新・全体確認

毎週日曜に実行。ベストプラクティスの最新化と全リポジトリの整合性確認を行う。

## 実行手順

### STEP 1: ベストプラクティス最新化

1. `~/my-freelance-sre/01-admin-setup/MyBestPractices.md` を読み、各セクションの内容を把握する

2. `~/.claude/reports/tech-feeds-latest.json` を読み、過去1週間の公式アップデートを確認する
   - ファイルが存在しない場合はスキップして手順3に進む
   - `errors` にフィード取得失敗があれば、該当ソースは WebSearch でカバーする

3. 以下のクエリで WebSearch を実行する（コミュニティ情報、各1〜2件）:
   - `Claude Code tips tricks reddit OR zenn OR qiita 2025`
   - `claude code CLAUDE.md best practices examples`

4. RSS + WebSearch の結果を MyBestPractices.md の各セクションに照らし合わせる:
   - **新しい知見・機能** → 該当セクションに追記
   - **古くなった記述（バージョン・手順・推奨事項）** → 更新または削除
   - **既存内容と重複するもの** → スキップ

5. ファイルを直接編集し、ファイル末尾の「最終更新」日付を今日の日付に更新する

6. 変更箇所を一覧で報告する（変更なしの場合もその旨を報告）

### STEP 2: known-failures.md の更新・棚卸し

**stagingの処理（`~/.claude/known-failures-staging.log` が存在する場合）**
1. staging を読み、各エントリを分析する
2. 以下の基準でパターン化する:
   - 既存の known-failures.md にない新しい失敗パターンか？
   - 原因が特定できるか（コマンドとエラー出力から推測）
   - 再現性がありそうか（1回限りのtypoは除外）
3. 該当するものは known-failures.md の適切なセクションに追記する（原因・OK例・NG例の形式で）
4. 処理済みの staging ファイルを削除する

**既存エントリの棚卸し**
5. `~/.claude/known-failures.md` を読む
6. 解決済み・陳腐化したパターンがないか確認する
7. 不要なエントリがあれば削除する

### STEP 3: 各リポジトリに /confirm を実行

以下の順で `/confirm` を実行し、問題を修復する:
1. `my-freelance-sre` リポジトリ
2. `content-pipeline` リポジトリ
3. `zenn-content` リポジトリ（存在する場合）

### STEP 4: 週次レポート出力

```markdown
## 週次レビューレポート: YYYY-MM-DD

### ベストプラクティス更新
- [変更内容 or 「変更なし」]

### known-failures.md 棚卸し
- [削除・追加内容 or 「変更なし」]

### リポジトリ確認結果
- my-freelance-sre: [✅ 問題なし / ⚠️ N件修復]
- content-pipeline: [✅ 問題なし / ⚠️ N件修復]

### 手動対応が必要な項目
- [項目と対応手順 or 「なし」]
```
