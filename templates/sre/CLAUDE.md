# {{PROJECT_NAME}} — Claude Code 行動指針（SRE）

> ハードルールは `.clauderules` を参照。

## 基本姿勢

- 回答・コメント・コミットは**全て日本語で**。
- 不明点は**作業前に確認**する（推測で進めない）。
- 本番環境への変更は **`terraform plan` → レビュー → `terraform apply`** の3ステップ。
- 作業完了後は **`git diff`** で差分サマリを提示する。

## プロジェクト概要

<!-- TODO: このプロジェクトの目的・技術スタックを記載 -->

## 環境構成

| 環境 | ディレクトリ | 用途 |
|---|---|---|
| staging | `environments/staging/` | 検証・テスト |
| production | `environments/prod/` | 本番（変更は要レビュー） |

## 参照ファイル

| ファイル | 内容 |
|---|---|
| `.clauderules` | ハードルール（本番保護・IAM・シークレット管理） |
| `CLAUDE.local.md` | 個人設定・環境固有情報（Git管理外） |
