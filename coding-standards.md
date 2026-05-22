# コーディング規約（全プロジェクト共通）

> **ここに書くもの**: AIがコードを生成・修正するとき守るべきテンプレート・命名規則・必須パターン（規約）。
> **書かないもの**: 実運用の経験則 → `best-practices.md` / 過去の失敗パターン → `known-failures.md`
> プロジェクト固有の規約は各 `.clauderules` の STYLE RULES を優先する。
> 最終更新: 2026-04-22

---

## 1. Bash スクリプト

### テンプレート（新規スクリプト作成時に従う）

```bash
#!/bin/bash
# スクリプト名.sh
# 目的を1行で（例: 毎日4時にガイドを1体生成してpush）
#
# cron登録（該当する場合）:
#   0 4 * * 1-6 /path/to/script.sh >> /path/to/cron.log 2>&1

set -euo pipefail

# --- 環境初期化 ---
export NVM_DIR="${HOME}/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# --- 定数 ---
PROJECT_DIR="${HOME}/<project-name>"
DATE=$(date +%Y-%m-%d)
LOG_PREFIX="[${DATE} $(date +%H:%M:%S)]"

# --- 共通関数の読み込み ---
source "${PROJECT_DIR}/scripts/lib.sh"

# --- メイン処理 ---
cd "$PROJECT_DIR" || { echo "${LOG_PREFIX} ERROR: ディレクトリが見つかりません"; exit 1; }

echo "${LOG_PREFIX} ===== 処理開始 ====="

# ... 処理 ...

echo "${LOG_PREFIX} ===== 処理完了 ====="
```

### 必須ルール

- `set -euo pipefail` — 未定義変数・パイプエラーの握りつぶし防止
- 変数は `"${VAR}"` でクォート — スペース含みパスでの事故防止
- ログは `${LOG_PREFIX} INFO/WARN/ERROR:` 形式 — cron.log 解析を容易に
- エラー時は `exit 1` — 後続cronジョブの誤実行防止
- cron登録コマンドをヘッダコメントに記載

### 命名規則

| 対象 | 規則 | 例 |
|---|---|---|
| スクリプトファイル | `kebab-case.sh` | `daily-guide.sh` |
| 関数名 | `snake_case` | `run_cmd()`, `run_step()` |
| 定数 | `UPPER_SNAKE_CASE` | `PROJECT_DIR`, `LOG_PREFIX` |
| ローカル変数 | `lower_snake_case` + `local` 宣言 | `local cmd_name="$1"` |
| プロジェクトDIR | `PROJECT_DIR` に統一 | ~~`PIPELINE_DIR`~~ ~~`GUIDE_DIR`~~ |

### 成功判定: exit code だけでなく成果物を検証する

外部プロセス（`claude --print`、API呼び出し等）の結果は exit code 0 でも期待する成果物が生成されていない場合がある。
処理の成功判定は「コマンドが正常終了したか」ではなく「期待する状態になったか」で行う。

```bash
# NG: exit code だけ見る（set -e 環境では $? チェックに届かないことがある）
json=$(run_cmd "research")
if [ $? -ne 0 ] || [ -z "$json" ]; then
    exit 1
fi

# OK: || で失敗を捕捉し、成果物の存在も検証する
json=$(run_cmd "research") || { echo "ERROR: research 失敗"; exit 1; }
if [ -z "$json" ]; then
    echo "ERROR: コマンドは成功したが結果が空"
    exit 1
fi
if [ ! -f "${expected_file}" ]; then
    echo "ERROR: コマンドは成功したが成果物が生成されていない"
    exit 1
fi
```

---

### デバッグ: 最小単位でテストする

問題が発生したら「どの層が壊れているか」を特定し、その層だけを切り出してテストする。全体パイプラインを何度も動かさない。

| 疑われる層 | テスト方法 |
|---|---|
| L1: `dispatch_ops` のパース | `echo` でサンプル JSON を直接渡す（API 不要） |
| L3: モデル出力のフォーマット | API を1回だけ呼んでファイルに保存 → 以降はそのファイルをリプレイ |
| L1: cron 環境・スクリプト全体 | `--dry-run` で確認 |

全体パイプライン実行は「各層が単体で OK であることを確認した後」の最終確認に1回だけ。

---

## 2. lib.sh パターン（拡張性設計）

各リポジトリの `scripts/lib.sh` に `run_cmd()` 関数を実装する。

- コマンド検索順: `${PROJECT_DIR}/.claude/commands/` → `${HOME}/.claude/commands/`
- frontmatter の `model:` を抽出して `claude --print` に渡す
- 参照実装: `~/.claude/scripts/lib.sh`（canonical版）。各リポジトリの `scripts/lib.sh` は委譲ラッパー

### run_cmd 用コマンドファイルのプロンプト要件

`run_cmd` から呼ばれるコマンド（`.claude/commands/*.md`）はプロンプト**冒頭**に以下を明記する。
冒頭に置くことで、モデルがツール選択を決める前に制約を認識できる。

```markdown
**実行環境**: `claude --print` で呼び出されている。標準出力がそのまま呼び出し元スクリプトの戻り値になる。
**使用可能なツール**: Read, Glob, Grep, WebSearch のみ
**出力形式**: 標準出力に以下のJSON配列のみを出力する。説明文・前置き・コードフェンス不要。
```

- 使用可能ツールを「使うな」ではなく「これだけ使える」と正の形で明示する
- `claude --print` という実行コンテキストを伝えることで、標準出力 = 戻り値という構造をモデルが理解する
- JSON配列を返す場合は `**必ず [ で始まるJSON配列で返すこと。{ で始まるオブジェクトは不可。**` を明示する（Haiku は指示が曖昧だとオブジェクト単体を返すことがある）
- `dispatch_ops` は JSON.parse 後に `Array.isArray` チェックを入れ、オブジェクト単体なら `[ops]` に包む防御実装を入れる（`lib.sh` 参照）

---

## 3. コードに歴史を残す（可読性原則）

コードは「何をしているか」だけでなく「なぜそうしているか」を伝える必要がある。
読む人が誰であれ（未来の自分・他のメンバー・AI）、文脈なしで意図を読み取れるようにする。

### 例外・オーバーライドには根拠を書く

理由が不明瞭な例外（外部サービスの仕様・歴史的経緯・検証済みだが説明できない挙動）をコードに混ぜるときは、必ずコメントに残す:

- **何が例外か** — どの値・動作が通常と違うか
- **なぜか** — 判明している理由。不明なら「理由不明」と明記
- **どう確認したか** — 実測・ドキュメント参照など、再検証の手がかりを残す

```bash
_OVERRIDE = {'monkeyking': 'wukong'}  # Wukong: ddragonKey=MonkeyKing だが Lolalytics は wukong
# 理由不明（Riot 内部の歴史的経緯と推測）。全 170 体を実測して確認済み（2026-04-14）。
```

「なんとなく動く」コードは後から触る人が外せなくなる。理由を書くことで「まだ必要か」を判断できる。

### 選ばなかった案も残す

設計の選択肢を比較して却下した場合、その理由を1行コメントで残す。
同じ検証を次の人が繰り返さなくて済む。

```python
# ddragonKey.lower() をベースに採用。
# re.sub('[^a-z0-9]', '', en.lower()) も試したが nunu/renata が 404 になるため却下（2026-04-14 実測）。
```

---

## 4. TODO / FIXME の書き方

`TODO` や `FIXME` は「何を」ではなく「いつ・なぜ・どうすれば」まで書く。
文脈のない TODO は誰も触れなくなる。

```python
# NG
# TODO: fix this

# OK
# TODO: Lolalytics の HTML 構造が変わったら正規表現を更新する
#       現在のパターン: 'wins against <a href=...> XX% of the time'（2026-04-14 確認）
```

```bash
# NG
# FIXME: なんか遅い

# OK
# FIXME: batch=200 のとき Gemini RPD 上限に近づく。上限緩和後に batch サイズを見直す（2026-04-14）
```

---

## 5. Python スクリプト

### ファイル操作: encoding="utf-8" を必ず明示する

`open()` はデフォルトエンコーディングを `locale.getpreferredencoding()` から取得する。
cron 環境ではロケールが最小設定になる場合があり、デフォルトが UTF-8 でないと日本語ファイルの読み書きで文字化けが発生する。
（実績: quality-fix.py で `ー` が U+FFFD に化け、次回実行で自己修復するバグが 2026-04-15 に確認）

```python
# NG: cron環境でロケール依存になる
with open(path) as f: ...
json.load(open(data_file))

# OK: 常に明示する
with open(path, encoding="utf-8") as f: ...
json.load(open(data_file, encoding="utf-8"))
```

- テキストファイル（.md / .json / .txt）の読み書き全てに適用する
- `urllib.request.urlopen` 等のネットワーク IO は対象外

---

## 6. Markdown ドキュメント

| ルール | 例 |
|---|---|
| 見出しは `#` から段階的に | `# > ## > ###`（レベルを飛ばさない） |
| 1ファイル1トピック | 長くなったら分割して参照させる |
| 最終更新日を冒頭に書く | `> 最終更新: 2026-04-14` |
| TODOはチェックボックス形式 | `- [ ]` / `- [x]` |

---

## 7. Git コミット

- Conventional Commits（日本語）: `feat:` / `fix:` / `chore:` / `docs:` / `refactor:` / `security:`
- 1コミット1論理変更（複数ファイルでもOK、複数目的はNG）
- WSL側の `git` で直接実行（リモートは HTTPS）
- **subject は "何をしたか"、body は "なぜしたか" を書く**
  - subject: diff を見ればわかること（変更の概要）
  - body: diff を見てもわからないこと（背景・制約・却下した代替案）

### cron 起点のコミットプレフィックス目安

| 起点・意図 | プレフィックス |
|---|---|
| 新規コンテンツ追加（対面ガイド生成・新記事ドラフト等） | `feat:` |
| データ修正・表記揺れ同期・既存コンテンツの直し | `fix:` |
| 派生データ再ビルド（data.json 再生成等）・設定更新・週次反映 | `chore:` |

cron 発の commit には subject 末尾に `(自動)` か `(自動生成)` を付けて、人間コミットと区別できるようにする。

---

## 8. git 自動化パターン（cron スクリプトの共通関数）

> **動機**: 自動化スクリプト各々が `git add .` / `git commit` / `git push` を手書きしていた結果、
> メッセージフォーマット・add 対象・エラーハンドリングが揃わず、`git add .` で意図しないファイル
> （未追跡メモ・ロック）を巻き込む事故が再発していた（2026-04-22 に5日分の未コミットを救出）。
> → 自動化の git 操作を L1 共通関数に寄せる。

### レイヤー分離

```
L1 (実行層)
├── ~/.claude/scripts/lib.sh
│   ├── run_cmd() / dispatch_ops()       [既存]
│   ├── auto_commit()                    [git 自動化エントリ]
│   └── auto_push()                      [リトライ付き push]
└── 各リポジトリ/scripts/*.sh             # 呼び出し側は auto_commit / auto_push を叩くだけ
```

### 4つの設計ルール

1. **git 操作は L1 共通関数に集約する。** 呼び出し側スクリプトに裸の `git add` / `git commit` / `git push` を書かない。
   → 例外は「既にコミット作成直前の特殊前処理がある」場合のみ。その場合もコメントで理由を残す。

2. **add は必ず明示パス。** `git add .` / `git add -A` は使わない。
   → 未追跡の作業メモ・ロックファイル・中間生成物を巻き込むため。
   → `auto_commit` の引数に commit 対象のパス列を渡す。

3. **コミットメッセージは Conventional Commits に揃える。** cron 起点の追加は `feat:`、修正は `fix:`、データ再生成や週次反映は `chore:`。
   → 人間が履歴を走査したとき、自動コミットとレビュー対象を素早く切り分けられる。

4. **push 失敗は沈黙させず exit 1。** cron.log にエラーが残り morning-report で可視化される。
   → 一時的な失敗（ネットワーク・同時 push 競合）は `auto_push` 内で指数バックオフリトライして救う。

### 関数シグネチャ

```bash
# auto_commit <path1> [path2 ...] -- <message>
#   - 指定パスを stage → commit する（push はしない）
#   - 変更なしなら何もせず return 0（冪等）
#   - DRY_RUN=1 のときは `git status --short <paths>` だけ表示して return
#
# auto_push
#   - 現在のブランチを origin に push する
#   - 失敗時は 30s / 90s で最大3回リトライ
#   - 全て失敗すれば return 1（呼び出し側が exit 1 に連鎖）
#   - DRY_RUN=1 のときはスキップして return 0
```

### 呼び出しパターン

単一コミットで済むスクリプト（週次反映など）:

```bash
source "${HOME}/.claude/scripts/lib.sh"

# ... 本処理 ...

auto_commit config/learnings.md -- "chore: 週次strategize結果を反映 ($(date +%Y-%m-%d)) (自動)"
auto_push || { echo "${LOG_PREFIX} ERROR: push 失敗"; exit 1; }
```

3段コミットするスクリプト（対面ガイド追加: 新規→同期→派生データ）:

```bash
auto_commit champions/*/matchups.md \
    -- "feat: 対面ガイド ${PROCESSED}件追加 (自動生成)"

auto_commit champions/*/matchups.md champions/*/guide.md \
    -- "fix: 対面ガイド 表記揺れ・得意苦手同期 (自動)"

auto_commit docs/data.json \
    -- "chore: data.json 再ビルド (対面ガイド追加後)"

auto_push || { echo "${LOG_PREFIX} ERROR: push 失敗"; exit 1; }
```

### 既存スクリプトの移行指針

- 新規スクリプト: 最初から `auto_commit` / `auto_push` を使う。`git add` を書かない。
- 既存スクリプト: 手書き git を `auto_commit` / `auto_push` に置換する。add 対象は `git add .` を分解して明示パスに書き下す（何が意図したコミット対象か確認するため）。
- trap EXIT で締めの commit を呼ぶスクリプト（503 リトライ対応等）は、trap 関数の中から `auto_commit` を呼んでよい。`set -e` 下での安全性は `auto_commit` 側で担保する。

### 準拠チェック

- `health-check.py` の `git_commit_hygiene` ルールが `scripts/*.sh` で `git add .` / `git add -A` / 裸の `git commit -m` を検出したら failing にする。
- `check-*` 系の単発ヘルスチェックスクリプトが git を触らない前提なら除外してよい。その場合も `auto_commit` を使わない根拠をスクリプト冒頭コメントに書く。

---

## 9. 今後の拡張ルール

プロジェクト固有の規約が必要な場合は、各リポジトリの `.clauderules` の `STYLE RULES` セクションに追記する。
ここには**全リポジトリ共通**のルールのみ記載する。
