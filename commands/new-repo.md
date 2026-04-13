---
description: テンプレートから新規リポジトリをセットアップ
---

# /new-repo — 新しいリポジトリのセットアップ

引数: `[リポジトリ名] [タイプ: base|sre]`（省略時は対話で確認）

---

## 手順

### 1. 引数の確認

引数が不足している場合は以下を確認する:
- **リポジトリ名**: 作成するディレクトリ名（例: `my-new-project`）
- **タイプ**: `base`（汎用）または `sre`（SRE/インフラ向け）

### 2. ディレクトリの準備

作成先は `~/` 配下とする。
既存ディレクトリがある場合は上書き前に確認する。

```
~/[リポジトリ名]/
```

### 3. テンプレートファイルのコピー

`~/.claude/templates/[タイプ]/` のファイルをコピーする。

**base タイプの場合:**
- `CLAUDE.md` → `CLAUDE.md`（`{{PROJECT_NAME}}` をリポジトリ名に置換）
- `CLAUDE.local.md` → `CLAUDE.local.md`
- `.clauderules` → `.clauderules`
- `.claudeignore` → `.claudeignore`
- `.gitignore` → `.gitignore`
- `README.md` → `README.md`（`{{PROJECT_NAME}}` をリポジトリ名に置換）

**sre タイプの場合:**
- base の全ファイルをコピー（ただし `CLAUDE.md`, `.clauderules`, `.claudeignore` は sre/ のものを使う）

### 4. .claude/ ディレクトリの作成

```
.claude/
├── commands/
│   └── learn.md       # /project:learn コマンド
└── agents/            # （空ディレクトリ）
```

`learn.md` の内容:
```markdown
# /project:learn — セッションの学びを保存

このセッションで得た技術的な学びや気づきを `CLAUDE.local.md` の末尾に追記する。
形式: `## 学び YYYY-MM-DD\n- [内容]`
```

### 5. git 初期化

```
git -C ~/[リポジトリ名] init
git -C ~/[リポジトリ名] add CLAUDE.md .clauderules .claudeignore .gitignore README.md .claude/
git -C ~/[リポジトリ名] commit -m "chore: リポジトリ初期化（テンプレートから生成）"
```

### 6. 完了報告

作成されたファイル一覧と、次にやること（`CLAUDE.md` の TODO 部分の編集）を提示する。

---

## 注意事項

- `CLAUDE.local.md` は `.gitignore` に含まれているので Git 管理外になる
- テンプレートを変更したい場合は `~/.claude/templates/` を直接編集する
- GitHub リポジトリも作成する場合は `gh repo create` を使う（SSH不要のHTTPS推奨）
