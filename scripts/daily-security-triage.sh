#!/bin/bash
# daily-security-triage.sh
# 毎日7時: GitHub Advisory (critical) を取得 → L3 Sonnet でトリアージ → CLAUDE.local.md に通知
# セキュリティコンテキスト — 技術ニュース（daily-tech-feeds.sh）とは分離
#
# cron登録:
#   0 7 * * * ${HOME}/.claude/scripts/daily-security-triage.sh >> ${HOME}/.claude/scripts/daily-security-triage.log 2>&1

set -euo pipefail

# --- 環境初期化 ---
export NVM_DIR="${HOME}/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

DATE=$(date +%Y-%m-%d)
LOG_PREFIX="[${DATE} $(date +%H:%M:%S)]"
ADVISORIES_JSON="${HOME}/.claude/reports/security-advisories-latest.json"
TRIAGE_JSON="${HOME}/.claude/reports/security-triage-latest.json"
LOCAL_MD="${HOME}/CLAUDE.local.md"

# --- ドライランフラグ ---
DRY_RUN=0
for _arg in "$@"; do [ "$_arg" = "--dry-run" ] && DRY_RUN=1; done

echo "${LOG_PREFIX} ===== セキュリティトリアージ開始 ====="

# STEP 1: L1 — GitHub Advisory (critical) を取得
echo "${LOG_PREFIX} L1: 脆弱性情報取得"
python3 "${HOME}/.claude/scripts/fetch-tech-feeds.py" \
    --config-override '{"feeds":[{"name":"GitHub Advisory (critical)","type":"github_advisories","severity":"critical"}]}' \
    --output "${ADVISORIES_JSON}" || {
    echo "${LOG_PREFIX} ERROR: 脆弱性情報取得失敗"
    exit 1
}

TOTAL=$(python3 -c "import json; print(json.load(open('${ADVISORIES_JSON}'))['total_entries'])")
echo "${LOG_PREFIX} INFO: ${TOTAL}件の critical advisory 取得"

if [ "${TOTAL}" = "0" ]; then
    echo "${LOG_PREFIX} INFO: 新規 critical advisory なし"
    echo "${LOG_PREFIX} ===== セキュリティトリアージ完了 ====="
    exit 0
fi

# STEP 2: L3 — トリアージ（Sonnet で判断）
echo "${LOG_PREFIX} L3: トリアージ実行"
triage_result=$(claude --print \
    --model sonnet \
    --output-format json \
    --allowed-tools "Read" \
    --disallowed-tools "Bash,Write,Edit,Glob,Grep,WebSearch,WebFetch,mcp__*" \
    -p "$(cat "${HOME}/.claude/commands/security-triage.md")" \
    < /dev/null 2>&1) || {
    echo "${LOG_PREFIX} ERROR: トリアージ失敗"
    exit 1
}

# JSON レスポンスから result を抽出
triage_json=$(echo "$triage_result" | node -e "
try {
    const d = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    const text = d.result || '';
    // コードフェンス除去
    const clean = text.replace(/\`\`\`json?\n?/g, '').replace(/\`\`\`/g, '').trim();
    process.stdout.write(clean);
} catch { process.exit(1); }
" 2>/dev/null) || {
    echo "${LOG_PREFIX} ERROR: トリアージ結果のパース失敗"
    exit 1
}

# 結果を保存
echo "$triage_json" > "${TRIAGE_JSON}"

# STEP 3: 通知 — relevant: true の項目を CLAUDE.local.md に記録
if [ "${DRY_RUN}" = "0" ]; then
    # 同日の既存エントリを削除（冪等性）
    grep -v "security-triage ${DATE}" "${LOCAL_MD}" > "${LOCAL_MD}.tmp" && mv "${LOCAL_MD}.tmp" "${LOCAL_MD}" || true

    NOTIFICATION=$(python3 -c "
import json, sys
try:
    triage = json.loads('''${triage_json}''')
    if not isinstance(triage, list):
        triage = [triage]
    relevant = [t for t in triage if t.get('relevant')]
    high = [t for t in relevant if t.get('urgency') == 'high']
    if high:
        items = '; '.join(t.get('reason', '')[:60] for t in high)
        print(f'🚨 HIGH {len(high)}件: {items}')
    elif relevant:
        items = '; '.join(t.get('reason', '')[:60] for t in relevant)
        print(f'⚠️ {len(relevant)}件: {items}')
    else:
        print('問題なし')
except Exception as e:
    print(f'パース失敗: {e}')
")
    echo "- ${DATE} security-triage: ${NOTIFICATION}" >> "${LOCAL_MD}"
fi

echo "${LOG_PREFIX} ===== セキュリティトリアージ完了 ====="
