#!/bin/bash
# daily-tech-feeds.sh
# 毎日6時: 技術フィードを取得し Discord に通知する
#
# cron登録:
#   0 6 * * * ${HOME}/.claude/scripts/daily-tech-feeds.sh >> ${HOME}/.claude/scripts/daily-tech-feeds.log 2>&1

set -euo pipefail

PROJECT_DIR="${HOME}/.claude"
DATE=$(date +%Y-%m-%d)
LOG_PREFIX="[${DATE} $(date +%H:%M:%S)]"

source "${HOME}/.claude/scripts/lib.sh"
FEEDS_OUTPUT="${HOME}/.claude/reports/tech-feeds-latest.json"

# --- ドライランフラグ ---
DRY_RUN=0
for _arg in "$@"; do [ "$_arg" = "--dry-run" ] && DRY_RUN=1; done

echo "${LOG_PREFIX} ===== フィード取得開始 ====="

python3 "${HOME}/.claude/scripts/fetch-tech-feeds.py" --output "${FEEDS_OUTPUT}" || {
    echo "${LOG_PREFIX} ERROR: フィード取得失敗"
    exit 1
}

if [ ! -f "${FEEDS_OUTPUT}" ]; then
    echo "${LOG_PREFIX} ERROR: 出力ファイルが生成されていない"
    exit 1
fi

TOTAL=$(python3 -c "import json; print(json.load(open('${FEEDS_OUTPUT}'))['total_entries'])")
ERRORS=$(python3 -c "import json; print(len(json.load(open('${FEEDS_OUTPUT}'))['errors']))")

echo "${LOG_PREFIX} INFO: ${TOTAL}件取得, エラー${ERRORS}件"

# Discord 通知（ドライランおよび0件の場合はスキップ）
if [ "${DRY_RUN}" = "0" ] && [ "${TOTAL}" -gt 0 ]; then
    ranked_json=$(run_cmd "rank-tech-feeds") || {
        echo "${LOG_PREFIX} WARN: ランク付け失敗。通知をスキップ"
        ranked_json=""
    }

    if [ -n "$ranked_json" ]; then
        DISCORD_BODY=$(python3 -c "
import json
items = json.loads('''${ranked_json}''')
rec = next((i for i in items if i.get('recommended')), items[0] if items else None)
lines = []
if rec:
    lines.append('**私のおすすめはこれっスよ！要チェックっス！**')
    lines.append(f\"⭐ **{rec['source']}** — {rec['title']}\")
    lines.append(rec.get('summary_ja', ''))
    lines.append(rec.get('url', ''))
    lines.append('')
rest = [i for i in items if not i.get('recommended')]
for n, item in enumerate(rest, 2):
    lines.append(f\"{n}. **{item['source']}** — {item['title']}\")
    lines.append(item.get('summary_ja', ''))
    lines.append(item.get('url', ''))
    lines.append('')
payload = {
    'embeds': [{
        'title': '📡 先輩！今日の最新ニュースっス！',
        'description': '\n'.join(lines).strip(),
        'color': 3447003,
        'footer': {'text': '${DATE} / ${TOTAL}件取得'}
    }]
}
print(json.dumps(payload))
")
        notify_discord "${DISCORD_WEBHOOK_TECH_FEEDS:-}" "$DISCORD_BODY"
    fi
fi

echo "${LOG_PREFIX} ===== フィード取得完了 ====="
