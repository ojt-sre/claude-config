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
解決済み: 2026-04-22。`~/.claude/scripts/lib.sh` の `dispatch_ops` で `{ ... }` オブジェクト単体を `[op]` に包む防御実装を追加（下の bracket-match ベース抽出ロジックに統合）。

## dispatch_ops: 前置きテキストに `[...]` リテラルがあると誤抽出する

症状: モデル出力が `選んだアイテム: [p0] 2026-04-21: ...\n[{...}]` のとき、`ERROR: JSON parse失敗` で落ちる。
原因: 旧実装は `raw.indexOf('[')` で最初の `[` を掴んで bracket-match していたため、preamble の `[p0]` を JSON 開始と誤解釈していた。
対処: 2026-04-22、`~/.claude/scripts/lib.sh` の `dispatch_ops` を修正。全 `[` 候補を列挙→各スライスを JSON.parse→全要素に `op` フィールドがある配列を採用。`{` 候補のフォールバックも同じ方式。テスト: `/tmp/dispatch_test.sh`（7ケース全 pass）。
再発予防: モデル出力パースで `indexOf` を使うときは「リテラルがプロンプト変数に含まれ得るか」を確認する。

## 連続失敗で打ち切る判定の閾値が低いと一時障害で誤検知する

症状: lol-guides-jp の `add-matchups.sh` が「Sonnet review 2件連続失敗 → spending limit と判断してバッチ終了」を出して途中で止まる。実際には 1.5h 後の次の cron で正常に動くので、spending limit ではなく一時的な API エラー（503・タイムアウト等）だった。早期 exit のため `===== 完了: 成功=N 失敗=M =====` 集計行が出ず、cron-add-matchups.sh が「完了行なし」アラートを CLAUDE.local.md に投げる。
原因: 連続失敗カウントの閾値が 2 と低く、一時障害を spending limit と誤判定していた。さらに早期 exit パスで集計行を出していなかったので、上位スクリプトが「ログ欠損」とみなしてアラートを発した。
対処: 2026-04-29、`add-matchups.sh` を修正。
- 閾値を 4 に引き上げ（一時障害が4連続することは稀。spending limit 検知としては緩いが、誤検知よりマシ）
- 判定文言を「spending limit と判断」→「一時障害の可能性が高いためバッチ中断」に改める
- 集計行を `trap '_finalize' EXIT` で出すよう変更（早期 exit でも必ず出る）
再発予防: 「連続 N 回失敗で打ち切る」型の監視は、N の妥当性を「実観測ベース」で決める。spending limit など本物の失敗が何回連続で出るか観測してから閾値を決定する。

## morning-report: ERROR ログを全数カウントすると一時エラーで偽アラートになる

症状: content-pipeline の `morning-report.sh` が `grep -c "ERROR" $cron.log` でエラー件数を集計していたため、リトライで救済される一時 ERROR（dispatch_ops 偽エラー・Gemini 503 など）まで「失敗」扱いになり、Discord に「記事作成に失敗してるっス」が偽アラートとして飛んでいた。実際は publish_queue に記事はちゃんと入っている。
原因: 「ERROR 行が cron.log に出ているか」で判定していたが、ERROR は中間ステップの一時的な失敗を含むため、最終成否の指標にならない。
対処: 2026-04-29、`morning-report.sh` を修正。
- `find publish_queue/zenn -newermt "00:00 today"` で「今夜追加された記事数」を算出
- ERROR_COUNT > 0 でも新規記事があれば失敗扱いしない（STATUS=OK_WITH_WARNINGS）
- 「今夜できた記事の有無」で判定するので、`feedback_cron_success_not_cumulative.md`（累積状態で判定しない）にも沿う
再発予防: 監視判定は「最終成果物が出たか」を一次基準にする。中間ログの ERROR は補助情報。

## dispatch_ops: 空配列 `[]` を「op が見つからない」と誤判定する

症状: editorial-review が「修正点なし」を `[]` だけで返したとき、`ERROR: op 配列/オブジェクトが見つかりません` で落ち、Discord にエラー通知が飛ぶ。記事自体は前段の draft / productize で publish_queue に入っているため実害はないが、毎日3:00の morning-report で偽アラートになる。
原因: `isOpArray` が `v.length > 0` を要求していた。空配列は「ops なし＝何もしないで正常終了」が正しい意味なのに失敗扱いされていた。
対処: 2026-04-29、`~/.claude/scripts/lib.sh` の `dispatch_ops` を修正。
- `isOpArray` から `length > 0` を外す（空配列も op 配列として受理）
- bracket 列挙ループは 2-pass にして「pass1: length>0 を優先 → pass2: 空配列も許容」。前置きに `[]` リテラルが混ざる場合に本物の op 配列より先に空配列を採用してしまう事故を防ぐ
- 空配列のときは `no-op: empty ops array (treated as success)` をログに出して識別可能にする

テスト: 空配列のみ / 前置き付き空配列 / 通常 op 配列 / 壊れ出力 / 前置き `[p0]` + 本物 / 前置き `[]` + 本物 の6ケース全 pass。
再発予防: モデル出力の「正常な空応答」が想定される箇所では、パース層で空配列を no-op として扱う設計にする。

## set -euo pipefail 環境での `|| echo 0` パターン

症状: `COUNT=$(find ... | wc -l || echo 0)` で COUNT が `"0\n0"` になり integer expression エラー
原因: find が exit 1 → pipefail でパイプ全体 exit 1 → wc -l が `0` を出力済みなのに `|| echo 0` がさらに `0` を追加する
対処: `|| echo 0` → `|| true` に変える。`wc -l` は空パイプでも `0` を出力するので `echo 0` は不要

```bash
# NG
COUNT=$(find "${DIR}" -name "*.md" 2>/dev/null | wc -l || echo 0)

# OK
COUNT=$(find "${DIR}" -name "*.md" 2>/dev/null | wc -l || true)
```

## lib.sh source 前の NVM 読み込み必須

症状: cron 環境で `ERROR: lib.sh requires Node.js (node) but it was not found in PATH` → スクリプトが即 exit 1
原因: lib.sh 冒頭で `node` の存在チェックをしているため、NVM 未読込の cron 環境では node が PATH に存在しない
対処: `source lib.sh` より前に NVM を読み込む（coding-standards.md のテンプレート参照）

```bash
# lib.sh を source する全スクリプトに必須
export NVM_DIR="${HOME}/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

source "${PROJECT_DIR}/scripts/lib.sh"  # ← この前に NVM を読む
```

## claude --print: frontmatter 付きファイルを -p で渡すと --- がオプション誤解釈される

症状: `-p "$(cat cmd.md)"` で frontmatter（`---\n...\n---`）含むファイルを渡すと `error: unknown option '---\n...'`
原因: Claude CLI が `---` で始まる引数をオプション名として解釈する。
対処: frontmatter を除去してから `--` で渡す（`lib.sh` の `run_cmd` と同じ方式）。

```bash
# NG
-p "$(cat "${HOME}/.claude/commands/cmd.md")"

# OK: frontmatter を除去して -- で渡す（2026-04-14 daily-security-triage.sh で実測）
_prompt=$(awk 'NR==1 && /^---$/{skip=1;next} skip && /^---$/{skip=0;next} !skip' "cmd.md")
claude --print ... -- "$_prompt"
```

## Zenn 記事タイトルは最大70文字

症状: Zenn デプロイで `Titleには最大70文字まで使用できます` エラーで保存失敗。git push は通るが Zenn 側のデプロイが中断される。
原因: Zenn の制約（タイトル長 ≤ 70 文字）。半角英数・空白も1文字としてカウント。
対処: 記事生成・タイトル決定時に `printf '%s' "$title" | wc -m` で文字数確認。70 を超えたら短縮する。
予防:
- ライターに「タイトルは70文字以内」を制約として渡す
- editorial-review でタイトル代替案を出すときは、各案の文字数を併記する
- publish 直前のチェックリストに「タイトル文字数 ≤ 70」を含める

実測: 2026-04-30、`Claude Code でモニタリング設計を加速する — CloudWatch Alarm の Terraform と Grafana JSON を一気通貫で書く`（81文字）でデプロイ失敗。`一気通貫で書く` → `一気に書く`、`の Terraform` 削除で 67 文字に短縮して再 push したら通った。

## Zenn 記事スラグはアカウント単位でユニーク・削除しても再利用不可

症状: zenn-content/articles/ にも content-pipeline の published/index.md にも痕跡がないスラグなのに、Zenn デプロイで `Slug「<slug>」はサイト内で既に使用されています` エラーで保存失敗。git push は通るが Zenn 側のデプロイが中断される。
原因: Zenn のスラグはアカウント単位でユニーク管理されており、**過去に公開して削除した記事のスラグも再利用できない**。articles/ から消しても、index.md に残らなくても、Zenn 内部の予約は残る。
対処: 公開前に `~/content-pipeline/scripts/check-slug.sh <slug>` で重複検査する。3ソース（zenn-content/articles/、published/index.md、config/reserved-slugs.txt）を見て、どれかに該当すれば exit 1 + 代替候補出力。重複が新たに判明したスラグは `config/reserved-slugs.txt` に YYYY-MM-DD と経緯コメント付きで追記して再発を防ぐ。
予防:
- publish-zenn.md / publish.md の手順にスラグ検査ステップを必須化済み（CLAUDE.md にも明文化、health-check.py で参照確認）
- 短い汎用名（`claude-code-memory-design` のような）は重複しやすいため、最初から focus キーワードを入れる（例: `-context-design` / `-pattern`）
- 削除した記事のスラグは reserved-slugs.txt に記録しておく（articles/ から消えるため検査対象から外れる）

実測: 2026-05-02、`claude-code-memory-design` でデプロイ失敗。`claude-code-memory-context-design` に変更して通過。同日付で reserved-slugs.txt に初期エントリとして記録した。

## Read tool が pdftoppm を検出できない（PATH にあっても失敗する）

症状: `poppler-utils` インストール済みで `which pdftoppm` が `/usr/bin/pdftoppm` を返す状態でも、Read tool で PDF を読もうとすると `pdftoppm is not installed. Install poppler-utils ...` で失敗する。
原因（推測）: Read tool のサブプロセス側で PATH が継承されていないか、Read tool が pdftoppm を独自パスで探していて見つけられていない。
対処: 手動で `pdftoppm` を叩いてページごとに PNG 化してから、PNG を Read tool で読み込む。

```bash
mkdir -p /tmp/pdf-img
pdftoppm -png -r 100 "/path/to/file.pdf" /tmp/pdf-img/page
# その後 /tmp/pdf-img/page-01.png 等を Read tool で1ファイルずつ読む
```

参考: テキストベースのPDFなら `pdftotext -layout` で .txt に抽出して Read で読む方が高速・低トークン。スライド・画像ベースのPDFのみ pdftoppm 経由で画像化する。
実測: 2026-05-16、PE-BANK 資料はテキストPDFで `pdftotext -layout` 一発OK、GEECHS JOB 資料はスライドPDF（テキスト0行）で `pdftoppm` 経由で18枚PNG化して読み込み成功。

## Sonnet 出力: 日本語語尾の「ス」が半角 ASCII の「S」に化ける

症状: `obsidian-tech-feeds` スキル（Sonnet）が「〜っス」口調で出力するレポートで、語尾の「ス」が半角アルファベット `S` で出力されることがある。`Stainless` のような英大文字を含む単語が周囲にあると頻発するが、関係ない箇所でも発生する。
原因: Sonnet のトークン化の癖。日本語コンテキスト中でも英大文字が近接すると、後続の `ス` が半角 `S` に化ける。プロンプトに全角で「っス」と書いても再発するため、モデル側で完全に防ぐのは難しい。
対処: 2026-05-20、3層で対策。
- 予防（プロンプト）: `commands/obsidian-tech-feeds.md` に「『ス』は必ず全角カタカナ（U+30B9）。半角 S に化けないよう注意」を明記
- 保険（後処理）: `scripts/daily-tech-feeds.sh` の Obsidian 書き出し直前で `sed 's/っS/っス/g'` をパイプで噛ます
- 既存ファイル一括修正: `/mnt/c/Obsidian/20_最新情報/*.md` で `sed -i` 実行（26ファイル中6ファイル、24箇所修正）

再発予防: 「っX」（X=ASCII大文字）の文字化けは日本語語尾全般で起こり得る。他のキャラクター口調スキル（「〜ッス」「〜ナリ」等）を作るときも、語尾を ASCII 化される可能性を考慮して後処理サニタイズを最初から入れる。
誤爆チェック: `grep -hoE "っS[A-Za-z]+"` で「っS」直後にアルファベットが続く例を確認したら 0 件。英単語の一部に巻き込まれるパターンはなかったため、`っS → っス` の単純置換で安全。

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
