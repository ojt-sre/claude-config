#!/bin/bash
# lib.sh - 全リポジトリ共通の関数ライブラリ（canonical版）
# 各リポジトリの scripts/lib.sh は source でこのファイルを読み込む。
# 呼び出し側は source 前に PROJECT_DIR, LOG_PREFIX を定義すること。

# node依存チェック（run_cmd/dispatch_ops がJSON解析にnode必須）
if ! command -v node &>/dev/null; then
    echo "ERROR: lib.sh requires Node.js (node) but it was not found in PATH." >&2
    echo "  Install via: nvm install --lts" >&2
    exit 1
fi

# コストログのパス（全リポジトリ共通）
COST_LOG="${HOME}/.claude/cost.log"

# Discord webhook URL（~/.claude/config/discord.env から読み込む）
_DISCORD_ENV="${HOME}/.claude/config/discord.env"
if [ -f "$_DISCORD_ENV" ]; then
    source "$_DISCORD_ENV"
fi

# notify_discord <webhook_url> <payload>
# Discord webhook に通知を送る。URL が空の場合はスキップ。
# payload は JSON 文字列。embeds を含む場合はそのまま渡す。
# 平文の場合は {"content": "..."} 形式で渡す。
notify_discord() {
    local webhook_url="$1"
    local payload="$2"
    if [ -z "$webhook_url" ]; then
        return 0
    fi
    curl -s -X POST "$webhook_url" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        > /dev/null 2>&1 || true
}

# run_cmd <コマンド名> [引数] [allowed-tools] [disallowed-tools]
# .claude/commands/<コマンド名>.md の内容を claude --print に渡す。
# ローカル優先・グローバルフォールバック。
# frontmatter に model: が指定されていれば --model フラグを自動付与する。
# 実行結果の使用量を ~/.claude/cost.log に記録する。
# allowed-tools 省略時は "Read,Glob,Grep,WebSearch"（L3読み取り専用）。
# disallowed-tools 省略時は "Write,Edit,Bash,mcp__*"（グローバル許可の上書き）。
# ファイル編集が必要なコマンドは allowed="Read,Glob,Grep,WebSearch,Write,Edit" disallowed="Bash,mcp__*" を渡す。
run_cmd() {
    local cmd_name="$1"
    local args="${2:-}"
    local allowed_tools="${3:-Read,Glob,Grep,WebSearch}"
    local disallowed_tools="${4:-Write,Edit,Bash,mcp__*}"

    # ローカル優先、なければグローバルを参照
    local local_file="${PROJECT_DIR}/.claude/commands/${cmd_name}.md"
    local global_file="${HOME}/.claude/commands/${cmd_name}.md"
    local cmd_file

    if [ -f "$local_file" ]; then
        cmd_file="$local_file"
    elif [ -f "$global_file" ]; then
        cmd_file="$global_file"
    else
        echo "${LOG_PREFIX:-} ERROR: コマンド ${cmd_name} が見つかりません" >&2
        return 1
    fi

    # frontmatter から model を抽出（---で囲まれたブロック内の model: 行）
    local model
    model=$(sed -n '1{/^---$/!q}; 2,/^---$/{/^model:/s/^model:[[:space:]]*//p}' "$cmd_file")

    # frontmatter を除いたプロンプトを生成（python3で$ARGUMENTS置換 — sedだと&等で壊れる）
    local prompt
    prompt=$(awk 'NR==1 && /^---$/{skip=1;next} skip && /^---$/{skip=0;next} !skip' "$cmd_file" \
             | ARGS="${args}" python3 -c "import sys,os; sys.stdout.write(sys.stdin.read().replace('\$ARGUMENTS', os.environ['ARGS']))")

    # DRY_RUN モード
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "${LOG_PREFIX:-[DRY-RUN]} DRY-RUN: run_cmd ${cmd_name} をスキップ" >&2
        echo "[]"
        return 0
    fi

    # JSON出力で実行し、コスト情報を抽出
    local json_output
    # CLAUDE_SUBPROCESS=1 でサブプロセスであることを hook に通知し Write を拒否させる
    json_output=$(CLAUDE_SUBPROCESS=1 claude --print --output-format json \
        --allowed-tools "$allowed_tools" \
        --disallowed-tools "$disallowed_tools" \
        ${model:+--model "$model"} -- "$prompt" < /dev/null 2>&1)
    local exit_code=$?

    # 使用量をログに記録
    local usage_usd duration_ms input_tokens output_tokens
    usage_usd=$(echo "$json_output" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.total_cost_usd||0)}catch{console.log(0)}" 2>/dev/null)
    duration_ms=$(echo "$json_output" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.duration_ms||0)}catch{console.log(0)}" 2>/dev/null)
    input_tokens=$(echo "$json_output" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));const u=d.usage||{};console.log((u.input_tokens||0)+(u.cache_creation_input_tokens||0)+(u.cache_read_input_tokens||0))}catch{console.log(0)}" 2>/dev/null)
    output_tokens=$(echo "$json_output" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log((d.usage||{}).output_tokens||0)}catch{console.log(0)}" 2>/dev/null)

    local repo_name
    repo_name=$(basename "${PROJECT_DIR}")
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(date +%Y-%m-%d)" "$(date +%H:%M:%S)" "$repo_name" "$cmd_name" \
        "$usage_usd" "$duration_ms" "$input_tokens" "$output_tokens" "$exit_code" >> "$COST_LOG"

    # 失敗時はエラー内容を stderr に出す（握り潰し防止）
    if [ $exit_code -ne 0 ]; then
        echo "${LOG_PREFIX:-} ERROR: run_cmd ${cmd_name} 失敗 (exit ${exit_code}): ${json_output}" >&2
    fi

    # 本文を標準出力に返す（JSONからresultフィールドを抽出）
    # コードフェンス（```json ... ```）を除去（known-failures.md 参照）
    local result_text
    result_text=$(echo "$json_output" | node -e "try{const d=JSON.parse(require('fs').readFileSync(0,'utf8'));process.stdout.write(d.result||'')}catch{}" 2>/dev/null)
    result_text=$(echo "$result_text" | sed 's/^```[a-z]*[[:space:]]*//' | sed 's/[[:space:]]*```$//')
    echo "$result_text"

    return $exit_code
}

# dispatch_ops <json> [base_dir]
# JSON ops配列を受け取り、ファイル操作を実行する（L1）。
# ops: write / append / copy / move / delete
# パスはbase_dir相対 or 絶対パスどちらも可。
# base_dir省略時は PROJECT_DIR を使う。
dispatch_ops() {
    local json="$1"
    local base_dir="${2:-${PROJECT_DIR}}"

    # DRY_RUN モード
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "$json" | node -e "
const ops = JSON.parse(require('fs').readFileSync(0, 'utf8'));
ops.forEach(op => console.log('[DRY-RUN]', JSON.stringify(op)));
" 2>/dev/null
        return 0
    fi

    echo "$json" | DISPATCH_BASE="$base_dir" node -e "
const fs = require('fs');
const path = require('path');
const base = process.env.DISPATCH_BASE;
const resolve = p => path.isAbsolute(p) ? p : path.join(base, p);
const raw = require('fs').readFileSync(0, 'utf8').trim();
// モデル出力から op 配列を頑健に抽出する。
// - 前置きテキストに [p0] など角括弧リテラルが混ざる場合がある
//   → raw.indexOf('[') は誤マッチするので、全 [ 候補を列挙して各々 bracket-match
// - 各候補スライスを JSON.parse し、配列内の全要素に op フィールドがあるものを採用
// - 配列が取れなければ { 候補も同様に試し、op 持ちオブジェクト単体なら [op] に包む
// coding-standards.md: Haiku はオブジェクト単体を返すことがある。本関数で吸収する。
function matchBracket(text, start, open, close) {
    let depth = 0, inStr = false, esc = false;
    for (let i = start; i < text.length; i++) {
        const c = text[i];
        if (esc) { esc = false; continue; }
        if (inStr && c.charCodeAt(0) === 92) { esc = true; continue; }
        if (c.charCodeAt(0) === 34) { inStr = !inStr; continue; }
        if (!inStr) {
            if (c === open) depth++;
            else if (c === close) { if (--depth === 0) return i; }
        }
    }
    return -1;
}
function isOpArray(v) {
    return Array.isArray(v) && v.length > 0
        && v.every(o => o && typeof o === 'object' && typeof o.op === 'string');
}
function isOpObject(v) {
    return v && typeof v === 'object' && !Array.isArray(v) && typeof v.op === 'string';
}
let ops = null;
// 1) raw 全体を直接 parse（綺麗に JSON だけ返ってくるケース）
try {
    const direct = JSON.parse(raw);
    if (isOpArray(direct)) ops = direct;
    else if (isOpObject(direct)) ops = [direct];
} catch(_) {}
// 2) [ 候補を全列挙して op 配列を探す
if (ops === null) {
    for (let i = 0; i < raw.length; i++) {
        if (raw[i] !== '[') continue;
        const end = matchBracket(raw, i, '[', ']');
        if (end === -1) continue;
        try {
            const parsed = JSON.parse(raw.slice(i, end + 1));
            if (isOpArray(parsed)) { ops = parsed; break; }
        } catch(_) {}
    }
}
// 3) { 候補を全列挙して op オブジェクト単体を探す（Haiku のフォールバック）
if (ops === null) {
    for (let i = 0; i < raw.length; i++) {
        if (raw[i] !== '{') continue;
        const end = matchBracket(raw, i, '{', '}');
        if (end === -1) continue;
        try {
            const parsed = JSON.parse(raw.slice(i, end + 1));
            if (isOpObject(parsed)) { ops = [parsed]; break; }
        } catch(_) {}
    }
}
if (ops === null) {
    // 失敗時は raw を <base>/logs/dispatch-failures/ に保存して調査可能にする
    // （cron.log は上書きされやすく、先頭500文字では足りないケースがあるため）
    // 削除: 各リポジトリ側で cleanup ジョブを設ける。
    //   content-pipeline は scripts/cleanup-drafts.sh が 7 日超を削除。
    //   他リポジトリで使う場合は同等のクリーンアップを追加すること。
    try {
        const logDir = path.join(base, 'logs/dispatch-failures');
        fs.mkdirSync(logDir, {recursive: true});
        const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
        const logPath = path.join(logDir, ts + '.txt');
        fs.writeFileSync(logPath, raw, 'utf8');
        console.error('ERROR: op 配列/オブジェクトが見つかりません → raw を保存:', logPath);
    } catch (e) {
        console.error('ERROR: op 配列/オブジェクトが見つかりません（raw保存失敗:', e.message + '）');
    }
    console.error('--- 受信した raw (先頭 500 文字) ---');
    console.error(raw.slice(0, 500));
    process.exit(1);
}
ops.forEach(op => {
    try {
        if (op.op === 'write') {
            fs.mkdirSync(path.dirname(resolve(op.path)), {recursive: true});
            fs.writeFileSync(resolve(op.path), op.content, 'utf8');
            console.log('write:', op.path);
        } else if (op.op === 'append') {
            fs.mkdirSync(path.dirname(resolve(op.path)), {recursive: true});
            fs.appendFileSync(resolve(op.path), op.content, 'utf8');
            console.log('append:', op.path);
        } else if (op.op === 'insert_after') {
            const filePath = resolve(op.path);
            const existing = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
            if (!existing.includes(op.after)) {
                console.error('ERROR: insert_after marker not found:', op.after);
                process.exit(1);
            }
            const updated = existing.replace(op.after, op.after + op.content);
            fs.mkdirSync(path.dirname(filePath), {recursive: true});
            fs.writeFileSync(filePath, updated, 'utf8');
            console.log('insert_after:', op.path, '(after:', op.after + ')');
        } else if (op.op === 'copy') {
            fs.mkdirSync(path.dirname(resolve(op.dest)), {recursive: true});
            fs.copyFileSync(resolve(op.src), resolve(op.dest));
            console.log('copy:', op.src, '->', op.dest);
        } else if (op.op === 'move') {
            fs.mkdirSync(path.dirname(resolve(op.dest)), {recursive: true});
            fs.renameSync(resolve(op.src), resolve(op.dest));
            console.log('move:', op.src, '->', op.dest);
        } else if (op.op === 'delete') {
            fs.unlinkSync(resolve(op.path));
            console.log('delete:', op.path);
        } else {
            console.error('WARN: unknown op:', op.op);
        }
    } catch (e) {
        console.error('ERROR:', op.op, JSON.stringify(op), e.message);
        process.exit(1);
    }
});
"
}
