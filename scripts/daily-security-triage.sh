#!/bin/bash
# daily-security-triage.sh
# 5分ごと: GitHub Advisory (critical/high, CVSS 7.0+) を取得 → 未処理分のみ L3 Sonnet でトリアージ
#          → Discord #security に通知。平日日中（JST 9-18時）は @everyone 付与
#
# cron登録:
#   */5 * * * * ${HOME}/.claude/scripts/daily-security-triage.sh >> ${HOME}/.claude/scripts/daily-security-triage.log 2>&1

set -euo pipefail

# --- 環境初期化 ---
export NVM_DIR="${HOME}/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

PROJECT_DIR="${HOME}/.claude"
DATE=$(date +%Y-%m-%d)
LOG_PREFIX="[${DATE} $(date +%H:%M:%S)]"
ADVISORIES_JSON="${HOME}/.claude/reports/security-advisories-latest.json"
PENDING_JSON="${HOME}/.claude/reports/security-advisories-pending.json"
TRIAGE_JSON="${HOME}/.claude/reports/security-triage-latest.json"
# 本日処理済みの GHSA ID を記録。日付入りにすることで翌日は自動リセット
NOTIFIED_FILE="${HOME}/.claude/reports/security-notified-${DATE}.txt"

source "${HOME}/.claude/scripts/lib.sh"

# --- ドライランフラグ ---
DRY_RUN=0
for _arg in "$@"; do [ "$_arg" = "--dry-run" ] && DRY_RUN=1; done

echo "${LOG_PREFIX} ===== セキュリティトリアージ開始 ====="

# STEP 1: L1 — GitHub Advisory (critical + high = CVSS 7.0+) を取得
echo "${LOG_PREFIX} L1: 脆弱性情報取得（critical + high）"
python3 "${HOME}/.claude/scripts/fetch-tech-feeds.py" \
    --config-override '{"feeds":[{"name":"GitHub Advisory","type":"github_advisories","severity":"critical"},{"name":"GitHub Advisory","type":"github_advisories","severity":"high"}]}' \
    --output "${ADVISORIES_JSON}" || {
    echo "${LOG_PREFIX} ERROR: 脆弱性情報取得失敗"
    exit 1
}

TOTAL=$(python3 -c "import json; print(json.load(open('${ADVISORIES_JSON}'))['total_entries'])")
echo "${LOG_PREFIX} INFO: ${TOTAL}件取得（CVSS 7.0+）"

if [ "${TOTAL}" = "0" ]; then
    echo "${LOG_PREFIX} INFO: advisory なし"
    echo "${LOG_PREFIX} ===== セキュリティトリアージ完了 ====="
    exit 0
fi

# STEP 2: 重複除去 — 本日すでに処理済みの GHSA ID を除外し pending に書き出す
NEW_COUNT=$(python3 -c "
import json, os

with open('${ADVISORIES_JSON}') as f:
    data = json.load(f)

# 本日処理済みを読み込み
seen = set()
if os.path.exists('${NOTIFIED_FILE}'):
    with open('${NOTIFIED_FILE}') as f:
        seen = set(line.strip() for line in f if line.strip())

# entries 内の重複も除去（critical と high の両クエリで同IDが来た場合）
seen_in_batch = set()
deduped = []
for e in data.get('entries', []):
    gid = e.get('ghsa_id', '')
    if gid and gid not in seen_in_batch:
        seen_in_batch.add(gid)
        deduped.append(e)

# 今回初めて見る advisory のみ pending へ
new_entries = [e for e in deduped if e.get('ghsa_id', '') not in seen]

# pending JSON を書き出し（triage が読む対象）
pending = dict(data)
pending['entries'] = new_entries
pending['total_entries'] = len(new_entries)
with open('${PENDING_JSON}', 'w') as f:
    json.dump(pending, f, ensure_ascii=False, indent=2)

# 新規分を処理済みにマーク（次の5分後に重複しないよう）
with open('${NOTIFIED_FILE}', 'a') as f:
    for e in new_entries:
        gid = e.get('ghsa_id', '')
        if gid:
            f.write(gid + '\n')

print(len(new_entries))
")

echo "${LOG_PREFIX} INFO: 未処理 ${NEW_COUNT}件"

if [ "${NEW_COUNT}" = "0" ]; then
    echo "${LOG_PREFIX} INFO: 新規 advisory なし（全件処理済み）"
    echo "${LOG_PREFIX} ===== セキュリティトリアージ完了 ====="
    exit 0
fi

# STEP 3: L3 — トリアージ（Sonnet で判断）
echo "${LOG_PREFIX} L3: トリアージ実行（${NEW_COUNT}件）"
# frontmatter（--- ブロック）を除去してから渡す。-p "$(cat file)" だと --- がオプション誤解釈される。
_prompt=$(awk 'NR==1 && /^---$/{skip=1;next} skip && /^---$/{skip=0;next} !skip' \
    "${HOME}/.claude/commands/security-triage.md")
triage_result=$(CLAUDE_SUBPROCESS=1 claude --print \
    --model sonnet \
    --output-format json \
    --allowed-tools "Read" \
    --disallowed-tools "Bash,Write,Edit,Glob,Grep,WebSearch,WebFetch,mcp__*" \
    -- "$_prompt" \
    < /dev/null 2>&1) || {
    echo "${LOG_PREFIX} ERROR: トリアージ失敗"
    exit 1
}

# JSON レスポンスから result を抽出
triage_json=$(echo "$triage_result" | node -e "
try {
    const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    const text = d.result || '';
    const clean = text.replace(/\`\`\`json?\n?/g, '').replace(/\`\`\`/g, '').trim();
    process.stdout.write(clean);
} catch { process.exit(1); }
" 2>/dev/null) || {
    echo "${LOG_PREFIX} ERROR: トリアージ結果のパース失敗"
    exit 1
}

echo "$triage_json" > "${TRIAGE_JSON}"

# STEP 4: 通知 — relevant: true の項目を Discord #security に送信
if [ "${DRY_RUN}" = "0" ]; then
    # 平日日中（JST 9-18時）は @everyone を付与。それ以外は通常通知
    JST_HOUR=$(TZ=Asia/Tokyo date +%H)
    JST_DOW=$(TZ=Asia/Tokyo date +%u)  # 1=月, 7=日
    if [ "${JST_DOW}" -le 5 ] && [ "${JST_HOUR}" -ge 9 ] && [ "${JST_HOUR}" -lt 18 ]; then
        MENTION="@everyone"
    else
        MENTION=""
    fi

    DISCORD_BODY=$(python3 -c "
import json, sys
try:
    triage = json.load(open('${TRIAGE_JSON}'))
    if not isinstance(triage, list):
        triage = [triage]
    relevant = [t for t in triage if t.get('relevant')]

    if not relevant:
        sys.exit(0)  # 関連なし → 通知不要

    mention = '${MENTION}'
    embeds = []
    for item in relevant[:5]:  # Discord の embed 上限に配慮して最大5件
        score = item.get('cvss_score', '不明')
        ghsa  = item.get('ghsa_id', '')
        title = item.get('title_ja', item.get('reason', '詳細不明'))
        color = 16711680 if item.get('urgency') == 'high' else 16753920  # high=赤, medium=橙

        def field(name, val):
            return {'name': name, 'value': (val or '(情報なし)')[:1024], 'inline': False}

        embeds.append({
            'title': '先輩！マズいっス！脆弱性報告っスよ！',
            'description': f'**[{ghsa}] CVSS: {score} — {title}**',
            'color': color,
            'fields': [
                field('📝 要約',    item.get('summary_ja', '')),
                field('🎯 影響範囲', item.get('impact_ja', '')),
                field('⚡ 一時対策', item.get('mitigation_temp_ja', '')),
                field('✅ 恒久対策', item.get('mitigation_perm_ja', '')),
            ],
            'footer': {'text': ghsa}
        })

    payload = {'embeds': embeds}
    if mention:
        payload['content'] = mention
    print(json.dumps(payload))
except Exception as e:
    print(json.dumps({'content': f'セキュリティトリアージ通知失敗: {e}'}))
")

    if [ -n "${DISCORD_BODY}" ]; then
        notify_discord "${DISCORD_WEBHOOK_SECURITY:-}" "${DISCORD_BODY}"
        RELEVANT_COUNT=$(echo "${triage_json}" | python3 -c \
            "import json,sys; t=json.load(sys.stdin); print(len([x for x in t if x.get('relevant')]))" \
            2>/dev/null || echo "?")
        echo "${LOG_PREFIX} INFO: Discord通知送信（relevant: ${RELEVANT_COUNT}件, @everyone: ${MENTION:-なし}）"
    else
        echo "${LOG_PREFIX} INFO: relevant なし、通知スキップ"
    fi
fi

echo "${LOG_PREFIX} ===== セキュリティトリアージ完了 ====="
