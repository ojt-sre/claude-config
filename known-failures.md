# known-failures — コマンド失敗パターン集

> **ここに書くもの**: 過去に失敗した具体的なコマンド・パターン。Bash実行前に確認する。
> **書かないもの**: 設計上の判断基準 → `best-practices.md` / テンプレート・命名規則 → `coding-standards.md`

---

## Git操作（WSL環境）

| やりたいこと | NG | OK |
|---|---|---|
| global config変更 | `git config --global ...`（hookでブロック） | `git -c key=value` をコマンドに直接渡す |
| リモートへのpush | SSH | リモートをHTTPSに設定: `git remote set-url origin https://...` |

## hookでブロックされるコマンド

| NG | 代替 |
|---|---|
| `curl * \| bash` / `curl * \| sh` | WebFetchツール |
| `npm install -g *` | プロジェクトローカルに`npm install` |
| `git config --global *` / `--system *` | `git -c key=value` でインライン指定 |
| `git push --force *` | ユーザーに依頼 |
| `git checkout --theirs <file>` / `git checkout --ours <file>` | ユーザーに依頼（マージコンフリクト解消中に片方の変更を丸ごと破棄する。取り返しがつかないため最重要リスク） |
| `git commit -m "$(cat <<'EOF'...EOF)"` でメッセージ内に危険パターン文字列が含まれる場合 | `git commit -F <file>` でメッセージをファイル経由にする（heredoc展開でメッセージ内容が誤検知される。validate-command.sh の改行正規化で修正済み） |

## Bash の `&&` チェーンと権限マッチ

allowルールはコマンド文字列の先頭でマッチする。`&&` チェーンすると先頭が変わり、マッチしない。

| やりたいこと | NG | OK |
|---|---|---|
| 別ディレクトリでgit操作 | `cd /path && git status` | `git -C /path status` |
| 複数コマンドの順次実行 | `cmd1 && cmd2`（1つのBash呼び出し） | 個別のBash呼び出しに分割する |

## WSL2: Puppeteer / Chrome起動不可

症状: `libnspr4.so: cannot open shared object file` → Chrome共有ライブラリ不足。
回避: `sharp`（libvips）でSVG→PNG変換。ブラウザ不要。
根本解決: `sudo apt install -y libnss3 libatk-bridge2.0-0 libdrm2 libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2t64 libpango-1.0-0 libcairo2`

## ~~WSL2: 日本語フォント不在~~（2026-04-02 解決済み）

`fonts-noto-cjk` + `~/.local/share/fonts/` 配置済み。再発確認: `fc-list :lang=ja`

## WSL環境: .exe呼び出し不要

`git.exe`/`gh.exe`は不要。全てUbuntu側の`git`/`gh`で完結する。スクリプト生成時に`.exe`を付けない。

## Python heredocのセキュリティ誤検知

症状: `python3 << 'EOF'`内に`r'\b'`等のブレース+クォート文字列があるとClaude Code内部チェックが「expansion obfuscation」として検知。
回避: スクリプトファイルに書き出して`python3 scripts/xxx.py`で実行。ヒアドキュメントは正規表現やブレースを含まない場合のみ。

## cron自律実行（claude --print）の落とし穴

NVM未ロード / コマンド不可 / 書き込み不可 / PowerShell連携など多数。
詳細はメモリ `feedback_cron_claude_print.md` に集約。

## set -euo pipefail 環境での run_cmd 戻り値チェック

症状: `json=$(run_cmd "cmd")` の後に `if [ $? -ne 0 ]` を書いても動かない。`run_cmd` が失敗するとそこでスクリプトが死に、`$?` チェックに到達しない。

```bash
# NG
json=$(run_cmd "cmd")
if [ $? -ne 0 ] || [ -z "$json" ]; then ...

# OK
json=$(run_cmd "cmd") || { echo "ERROR: cmd 失敗"; exit 1; }
if [ -z "$json" ]; then ...
```

## settings.json の Write(**) が --allowed-tools を貫通する

症状: `claude --print --allowed-tools "Read,Glob"` と指定しても、`settings.json` に `Write(**)` があると子プロセスが Write ツールを使える。
原因: `permissions.allow` はツールの自動承認を制御し、`--allowed-tools` より優先される。
対処:
1. `settings.json` から `Write(**)` / `Edit(**)` を削除する
2. 対話セッション用に `PermissionRequest` hook（`auto-approve-edit-write.sh`）で自動承認する
3. サブプロセス（`run_cmd`）には `CLAUDE_SUBPROCESS=1` を付与し、hook が Write を明示的に deny する
4. コマンドプロンプト冒頭に「使用可能なツール」を明示してモデルがWriteを使わないよう誘導する（→ coding-standards.md 参照）

## --print モードでは Write が自動承認されない

`claude --print`（非対話）モードでは、`settings.json` に `Write(**)` がなければ Write ツールは拒否される。
`PermissionRequest` hook も非対話モードでは動作しない。
→ この性質を利用して、`settings.json` から `Write(**)` を外すことでサブプロセスの Write を抑制できる。

## claude --print: フラグ多数時にプロンプト位置引数が認識されない

症状: `claude --print --model haiku --output-format json --allowed-tools "Read" "$(cat prompt.md)"` → `Error: Input must be provided either through stdin or as a prompt argument`
原因: `--allowed-tools` 等のフラグが多い場合、末尾の位置引数がプロンプトとして認識されない。
対処: `-p` フラグで明示的に渡す → `claude --print ... -p "$(cat prompt.md)"`

## dispatch_ops: JSONをコードフェンスで囲んで返すモデル

症状: `SyntaxError: Unexpected token '`'` — haiku 等が JSON を ` ```json ``` ` で囲んで返す。
解決済み: `content-pipeline/scripts/lib.sh` の `dispatch_ops` でコードフェンスを除去済み。
再発時: 他リポジトリの `lib.sh` にも同じ修正を適用する。

## Python regex: 全角括弧は group 区切りにならない

症状: `（Lv\d+）?` が「`）` だけを省略可能」と解釈され、意図した `(?:（Lv\d+）)?` と異なる挙動になる。

原因: Python の `re` モジュールでは ASCII の `(` `)` だけが regex の group 区切り。全角の `（` `）`（U+FF08/FF09）はリテラル文字として扱われる。そのため `？` の適用範囲が直前の1文字（`）`）のみになる。

```python
# NG: 「）だけ省略可能」＝（Lv\d+ は必須になる
r"CD\d+秒（Lv\d+）?"

# OK: グループ全体を省略可能にする
r"CD\d+秒(?:（Lv\d+）)?"
```

## dispatch_ops: Haiku が JSON配列でなくオブジェクトを返す

症状: `ERROR: JSON配列が見つかりません` — Haiku が `[{...}]` でなく `{...}` を返す。
原因: Haiku は出力形式の指示が曖昧だと単一オブジェクトで返すことがある。
対処: コマンドプロンプトの出力形式に `**必ず [ で始まるJSON配列で返すこと。{ で始まるオブジェクトは不可。**` を明示する。
