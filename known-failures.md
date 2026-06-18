# known-failures — コマンド失敗パターン集

> **ここに書くもの**: 過去に失敗した具体的なコマンド・パターン。Bash実行前に確認する。
> **書かないもの**: 設計上の判断基準 → `best-practices.md` / テンプレート・命名規則 → `coding-standards.md`
> 各項は「症状 → 直し方」を最短で。長い経緯は削り、再現に要る情報だけ残す。

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
| `git checkout --theirs <file>` / `git checkout --ours <file>` | ユーザーに依頼（マージ中に片方を丸ごと破棄。不可逆で最重要リスク） |
| `git commit -m "$(cat <<'EOF'...EOF)"` でメッセージに危険パターン文字列 | `git commit -F <file>` でファイル経由にする（heredoc展開で誤検知。validate-command.sh の改行正規化で修正済み） |

## Bash の `&&` チェーンと権限マッチ

allowルールはコマンド文字列の先頭でマッチする。`&&` チェーンすると先頭が変わりマッチしない。

| やりたいこと | NG | OK |
|---|---|---|
| 別ディレクトリでgit操作 | `cd /path && git status` | `git -C /path status` |
| 複数コマンドの順次実行 | `cmd1 && cmd2`（1呼び出し） | 個別のBash呼び出しに分割 |

## WSL2: Puppeteer / Chrome起動不可

症状: `libnspr4.so: cannot open shared object file`（共有ライブラリ不足）。
回避: `sharp`（libvips）でSVG→PNG変換（ブラウザ不要）。
根本解決: `sudo apt install -y libnss3 libatk-bridge2.0-0 libdrm2 libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2t64 libpango-1.0-0 libcairo2`

## WSL環境: .exe呼び出し不要

`git.exe`/`gh.exe`は不要。全てUbuntu側の`git`/`gh`で完結。スクリプト生成時に`.exe`を付けない。

## Python heredocのセキュリティ誤検知

症状: `python3 << 'EOF'`内に`r'\b'`等のブレース+クォート文字列があると内部チェックが「expansion obfuscation」検知。
回避: スクリプトファイルに書き出して`python3 scripts/xxx.py`実行。heredocは正規表現・ブレースを含まない場合のみ。

## cron自律実行（claude --print）の落とし穴

NVM未ロード / コマンド不可 / 書き込み不可 / PowerShell連携など多数。詳細はメモリ `feedback_cron_claude_print.md`。

## set -euo pipefail 環境での run_cmd 戻り値チェック

症状: `json=$(run_cmd "cmd")` の後の `if [ $? -ne 0 ]` が効かない（run_cmd 失敗時そこで死に、$? チェックに到達しない）。

```bash
# NG
json=$(run_cmd "cmd")
if [ $? -ne 0 ] || [ -z "$json" ]; then ...
# OK
json=$(run_cmd "cmd") || { echo "ERROR: cmd 失敗"; exit 1; }
if [ -z "$json" ]; then ...
```

## settings.json の Write(**) が --allowed-tools を貫通する

症状: `--allowed-tools "Read,Glob"` でも `settings.json` に `Write(**)` があると子プロセスが Write を使える（`permissions.allow` が優先）。
対処:
1. `settings.json` から `Write(**)` / `Edit(**)` を削除
2. 対話用は `PermissionRequest` hook（`auto-approve-edit-write.sh`）で自動承認
3. サブプロセス（`run_cmd`）には `CLAUDE_SUBPROCESS=1` を付与し hook が Write を deny
4. コマンドプロンプト冒頭に「使用可能なツール」を明示（→ coding-standards.md）

## --print モードでは Write が自動承認されない

`claude --print`（非対話）では `settings.json` に `Write(**)` が無ければ Write は拒否される（`PermissionRequest` hook も非対話では動かない）。→ この性質を利用し、`Write(**)` を外すことでサブプロセスの Write を抑制できる。

## claude --print: フラグ多数時にプロンプト位置引数が認識されない

症状: `claude --print --model haiku --output-format json --allowed-tools "Read" "$(cat prompt.md)"` → `Input must be provided either through stdin or as a prompt argument`。
対処: `-p` フラグで明示的に渡す → `claude --print ... -p "$(cat prompt.md)"`

## claude --print: frontmatter 付きファイルを -p で渡すと --- が誤解釈される

症状: `-p "$(cat cmd.md)"` で frontmatter（`---...---`）含むと `error: unknown option '---...'`（CLI が `---` をオプション名と解釈）。
対処: frontmatter を除去して `--` で渡す（`lib.sh` の `run_cmd` と同じ）。

```bash
# OK（2026-04-14 daily-security-triage.sh で実測）
_prompt=$(awk 'NR==1 && /^---$/{skip=1;next} skip && /^---$/{skip=0;next} !skip' "cmd.md")
claude --print ... -- "$_prompt"
```

## dispatch_ops: JSONをコードフェンスで囲んで返すモデル

症状: `SyntaxError: Unexpected token '`'` — haiku 等が JSON を ` ```json ``` ` で囲む。
解決済み: `content-pipeline/scripts/lib.sh` の `dispatch_ops` でフェンス除去済み。再発時は他リポジトリの `lib.sh` にも同修正。

## dispatch_ops: Haiku が JSON配列でなくオブジェクトを返す

症状: `ERROR: JSON配列が見つかりません` — Haiku が `[{...}]` でなく `{...}` を返す（指示が曖昧だと単一オブジェクト）。
対処: プロンプトに `**必ず [ で始まるJSON配列で返すこと。{ で始まるオブジェクトは不可。**` を明示。
解決済み: 2026-04-22、`~/.claude/scripts/lib.sh` の `dispatch_ops` で `{...}` 単体を `[op]` に包む防御を追加（下の bracket-match 抽出に統合）。

## dispatch_ops: 前置きテキストに `[...]` リテラルがあると誤抽出する

症状: 出力が `選んだアイテム: [p0] ...\n[{...}]` のとき `ERROR: JSON parse失敗`（旧実装は最初の `[` を掴み preamble の `[p0]` を JSON 開始と誤認）。
対処: 2026-04-22 `dispatch_ops` 修正。全 `[` 候補を列挙→各スライスを JSON.parse→全要素に `op` がある配列を採用。`{` フォールバックも同方式。テスト `/tmp/dispatch_test.sh`（7ケース pass）。
予防: モデル出力パースで `indexOf` を使うときは「リテラルがプロンプト変数に含まれ得るか」を確認。

## dispatch_ops: 空配列 `[]` を「op が見つからない」と誤判定する

症状: editorial-review が「修正点なし」を `[]` で返すと `ERROR: op 配列/オブジェクトが見つかりません`（`isOpArray` が `length > 0` を要求していた）。記事自体は前段で publish_queue に入るので実害なし、だが morning-report が偽アラート。
対処: 2026-04-29 `dispatch_ops` 修正。`isOpArray` から `length>0` を外す。bracket 列挙は 2-pass（pass1: length>0優先 → pass2: 空配列許容）で前置き `[]` の誤採用を防ぐ。空配列時は `no-op: empty ops array (treated as success)` をログ。
予防: 正常な空応答が想定される箇所はパース層で空配列を no-op 扱いに設計する。

## Python regex: 全角括弧は group 区切りにならない

症状: `（Lv\d+）?` が「`）` だけ省略可能」と解釈される。Python `re` は ASCII `( )` だけが group 区切りで、全角 `（ ）`（U+FF08/FF09）はリテラル。

```python
r"CD\d+秒（Lv\d+）?"        # NG: ）だけ省略可能＝（Lv\d+ は必須
r"CD\d+秒(?:（Lv\d+）)?"    # OK: グループ全体を省略可能
```

## 連続失敗で打ち切る判定の閾値が低いと一時障害で誤検知する

症状: lol-guides-jp の `add-matchups.sh` が「review 2件連続失敗 → spending limit と判断」で途中終了。実際は一時 API エラー（503・タイムアウト）で次 cron では正常。早期 exit で集計行が出ず、上位が「完了行なし」アラート。
対処: 2026-04-29、閾値を 2→4 に引上げ、文言を「一時障害の可能性が高いためバッチ中断」に、集計行を `trap '_finalize' EXIT` で必ず出すよう変更。
予防: 「連続 N 回で打ち切る」型は N を実観測ベースで決める（本物の失敗が何回連続するか観測してから）。

## morning-report: ERROR ログを全数カウントすると一時エラーで偽アラート

症状: `grep -c "ERROR" cron.log` で集計したため、リトライで救済される一時 ERROR（dispatch_ops偽エラー・Gemini 503）まで失敗扱いになり Discord 偽アラート。実際は publish_queue に記事は入っている。
対処: 2026-04-29、`find publish_queue/zenn -newermt "00:00 today"` で今夜の記事数を算出。ERROR>0 でも新規記事があれば失敗扱いしない（STATUS=OK_WITH_WARNINGS）。
予防: 監視は「最終成果物が出たか」を一次基準に。中間ログの ERROR は補助情報。関連 [[feedback_cron_success_not_cumulative]]。

## set -euo pipefail 環境での `|| echo 0` パターン

症状: `COUNT=$(find ... | wc -l || echo 0)` で COUNT が `"0\n0"` になり integer エラー（find が exit 1 → pipefail でパイプ全体失敗 → wc が `0` 出力済みなのに更に `0` 追加）。
対処: `|| echo 0` → `|| true`。`wc -l` は空パイプでも `0` を出すので `echo 0` 不要。

```bash
COUNT=$(find "${DIR}" -name "*.md" 2>/dev/null | wc -l || echo 0)  # NG
COUNT=$(find "${DIR}" -name "*.md" 2>/dev/null | wc -l || true)    # OK
```

## lib.sh source 前の NVM 読み込み必須

症状: cron で `ERROR: lib.sh requires Node.js (node) but it was not found in PATH` → 即 exit 1（lib.sh 冒頭の node 存在チェックに NVM 未読込で引っかかる）。
対処: `source lib.sh` より前に NVM を読む。

```bash
export NVM_DIR="${HOME}/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
source "${PROJECT_DIR}/scripts/lib.sh"  # ← この前に NVM
```

## Zenn 記事タイトルは最大70文字

症状: `Titleには最大70文字まで使用できます` で保存失敗（git push は通るが Zenn デプロイが中断）。半角英数・空白も1文字。
対処: タイトル決定時に `printf '%s' "$title" | wc -m` で確認、70超なら短縮。ライターに70字制約を渡す / editorial-review のタイトル代替案に文字数併記 / publish 前チェックに含める。
実測: 2026-04-30、81文字でデプロイ失敗 → 67文字に短縮して通過。

## Zenn 記事スラグはアカウント単位でユニーク・削除しても再利用不可

症状: articles/ にも published/index.md にも痕跡が無いスラグで `Slug「<slug>」はサイト内で既に使用されています`。過去に公開して削除したスラグも Zenn 内部の予約が残り再利用不可。
対処: 公開前に `~/content-pipeline/scripts/check-slug.sh <slug>` で3ソース（articles/・index.md・`config/reserved-slugs.txt`）を重複検査。判明した重複は reserved-slugs.txt に日付＋経緯コメント付きで追記。
予防: publish-zenn.md / publish.md にスラグ検査を必須化済み。短い汎用名は重複しやすいので最初から focus キーワードを入れる。削除記事のスラグは reserved-slugs.txt に記録。
実測: 2026-05-02、`claude-code-memory-design` 失敗 → `claude-code-memory-context-design` で通過。

## Zenn デプロイ: 短時間に複数記事を push すると「投稿数の上限」で一部保留

症状: 複数記事を1コミットで push → `次の記事は投稿数の上限に達したためデプロイされませんでした: <slug>` で一部のみ未公開。git push は exit 0、ファイルもリポジトリに入る。Zenn デプロイ段階でのみ弾かれる。正確な上限・リセット時間は FAQ が JS レンダリングで未確認（経験則: 日次〜数時間でリセットと推測）。
対処: 保留記事は `published: true` のまま残るので、制限明けに再 push（`git commit --allow-empty` でも可）で次回デプロイが拾う。
予防: 新規記事は1〜2本ずつ時間を空けて push。3本以上を一度に出さない。
実測: 2026-05-31、3記事 push で1本（terraform-drift-detection-state-import-flow）が上限保留。

## Read tool が pdftoppm を検出できない（PATH にあっても失敗）

症状: `which pdftoppm` が通る状態でも Read tool の PDF 読込が `pdftoppm is not installed`（推測: Read tool 側で PATH 非継承 or 独自パス探索）。
対処: 手動で `pdftoppm` で PNG 化してから PNG を Read。

```bash
mkdir -p /tmp/pdf-img
pdftoppm -png -r 100 "/path/to/file.pdf" /tmp/pdf-img/page
# /tmp/pdf-img/page-01.png 等を1ファイルずつ Read
```

参考: テキストPDFは `pdftotext -layout` で .txt 抽出が高速・低トークン。スライド/画像PDFのみ pdftoppm 経由。
実測: 2026-05-16、テキストPDFは pdftotext 一発、スライドPDF（テキスト0行）は pdftoppm で18枚PNG化して成功。

## Sonnet 出力: 日本語語尾の「ス」が半角 ASCII の「S」に化ける

症状: Sonnet の「〜っス」口調で語尾の「ス」が半角 `S` になる（英大文字単語が近接すると頻発、無関係箇所でも発生）。トークン化の癖でプロンプトに全角で書いても再発。
対処: 2026-05-20、3層対策。①プロンプトに「『ス』は全角カタカナ U+30B9」明記 ②後処理で書き出し直前に `sed 's/っS/っス/g'` ③既存ファイルを `sed -i` で一括修正。
予防: 「っX」（X=ASCII大文字）の化けは語尾全般で起こる。他のキャラ口調スキルでも後処理サニタイズを最初から入れる。`grep -hoE "っS[A-Za-z]+"` で誤爆 0 件確認済み（単純置換で安全）。

## grep -v はファイル名でなく「中身」をフィルタする

症状: cron-add-matchups.sh が4日間（2026-05-26〜29）「成功=0 失敗=0」でサイレント停止。`cat missing-*.txt | grep -v subrole | wc -l` で残数を数えていたが、`grep -v subrole` は**ファイルの中身**から "subrole" を含む行を除外する。中身に "subrole" 文字列が無いため subrole キュー4995件が丸ごとカウントされ、段判定を誤った。
対処: ファイル**名**で除外するならグロブ。`cat missing-[!s]*.txt`（missing- の次が s 以外）。requeue 側も `requeue-[!s]*.txt` に統一（2026-05-29）。
予防: 「ファイル名で絞る」のか「中身で絞る」のかを意識する。名前→グロブ、中身→grep。

## dry-run で「正常」を確認しても、入力データ投入後は再度 dry-run

症状: 上記 cron-add-matchups 停止は、実装時（2026-05-25）の dry-run で「正しく動く」と確認済みなのに本番で発生。dry-run 時点では `missing-subrole-*.txt` が未生成（空）で MISSING_TOTAL=0 だった。その**後**に3421件を投入したことで grep -v バグが初めて発火。テストは嘘をついていない——前提（入力データ）が後から変わったのに再確認しなかったのが穴。
対処: 「生成処理」と「消費処理」を同セッションで触ったら、生成→消費の順で、**データ投入の後に消費側を再テスト**する。可能なら dry-run に「末端で実際に何件処理するか」も出力させる。詳細 [[feedback_retest_after_input_change]]。

## pgrep -f <pattern> は待機ループ自身のコマンドラインを自己検出する

症状: `until ! pgrep -f cron-add-matchups.sh; do sleep 30; done` で cron 完了を待つと、cron は終了済みなのに永久に抜けない。`pgrep -f` はフルコマンドライン照合で、待機ループ自身のコマンドラインに pattern 文字列が含まれ自己マッチする。
対処: 完了判定は「プロセス有無」でなく**ログの終了マーカー grep**（`until grep -q "===== .* 終了" log; do sleep 30; done`）。どうしてもプロセス監視なら起動形態で絞る（`pgrep -f "bash.*cron-add-matchups.sh"`）。
予防: `pgrep -f` を待機条件に使うときは「待機コマンド自身が pattern にマッチしないか」を確認。`run_in_background` の until ループは特に危険。

## /mnt/c（Windows・CRLF）ファイルの複数行ツール出力が崩れる

症状: `/mnt/c/Obsidian/` 等の Windows 側ファイルを `grep -n` / `Read` で読むと複数行出力が崩れる（行の重複・前行の上書き・断片の氾濫）。`grep -c` / `wc -l` 等の**単一数値出力は正常**。Edit/Write の反映自体は正常（表示だけの問題）。
原因（2026-06-16 切り分け確定）: **CRLF の `\r`**。各行末の `\r` が端末でカーソルを列0に戻し後続文字を上書きする。証拠: ①単一数値=正常 ②ローカル(LF)の複数行=正常 ③/mnt/c の生 grep=崩れる ④`\r` を抜く（LF保存/`tr -d '\r'`）と完全に綺麗 → `\r` が主犯。
対処（根本対処済み 2026-06-18）: /mnt/c は **`mcat` で読む**。`~/.claude/scripts/mcat`（`~/.local/bin/mcat` に symlink）が `\r` を除去して出力する（LF ファイルには no-op）。さらに `PreToolUse` hook `read-grep-guard.sh` が Read/Grep tool で `/mnt/c`（symlink 裏口 `~/obsidian_vault` 含む）を読もうとすると exit 2 で止め、mcat へ誘導する＝「手で tr するのを忘れても崩れない」。

```bash
mcat -n "/mnt/c/path/file.md"                 # Read 相当（行番号付き）
mcat "/mnt/c/path/file.md" | grep -n "pattern" # grep -n は元の行番号と一致
grep -rn "pattern" /mnt/c/dir | tr -d '\r'     # ディレクトリ grep は出力の \r を剥がす
```

- Edit/Write は実体に作用するので CRLF でも正常（old_string は1行内で完結させる＝改行を跨がない）。状態確認は `grep -c` 等の数値で裏取り。
- LF へ一括変換は避ける（Obsidian/Windows が再 CRLF 化・git ノイズ）。読み出し側で吸収する方式を採用。
- hook 追加直後はセッション再起動するまで発火しない場合がある。再起動後は Read/Grep tool が自動で止まる。
