---
description: リポジトリ健全性チェック（L1機械 + L3判断）
---

# /confirm — リポジトリ健全性チェック

## 手順

### STEP 1: L1機械チェック

```bash
python3 ~/.claude/scripts/health-check.py [カレントディレクトリ] --fix
```

結果を読み、NG項目を確認する。`--fix`で自動修復可能な項目（ディレクトリ作成等）は自動処理済み。

### STEP 2: L3判断チェック（AIにしかできない項目）

- CLAUDE.md のルールに「なぜか」が書かれているか（理由のないルールは追記する）
- .clauderules のHARD RULESが本番保護・シークレット禁止を含むか
- 設定ファイル間の矛盾がないか（CLAUDE.md↔.clauderules↔settings.json）

### STEP 3: レポート出力

```
## 確認完了: [リポジトリ名]
- L1チェック: N/N 合格（自動修復M件）
- L3チェック: 問題なし / [指摘事項]
- 手動対応: なし / [項目]
```
