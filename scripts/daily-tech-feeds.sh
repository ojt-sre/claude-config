#!/bin/bash
# daily-tech-feeds.sh
# 毎日6時: 技術フィードを取得し、新着があれば CLAUDE.local.md に記録
# 収集コンテキスト（L1）— 分析は weekly-review.sh（L3）が担当
#
# cron登録:
#   0 6 * * * ${HOME}/.claude/scripts/daily-tech-feeds.sh >> ${HOME}/.claude/scripts/daily-tech-feeds.log 2>&1

set -euo pipefail

DATE=$(date +%Y-%m-%d)
LOG_PREFIX="[${DATE} $(date +%H:%M:%S)]"
FEEDS_OUTPUT="${HOME}/.claude/reports/tech-feeds-latest.json"
LOCAL_MD="${HOME}/CLAUDE.local.md"

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

# 件数を取得
TOTAL=$(python3 -c "import json; print(json.load(open('${FEEDS_OUTPUT}'))['total_entries'])")
ERRORS=$(python3 -c "import json; print(len(json.load(open('${FEEDS_OUTPUT}'))['errors']))")

echo "${LOG_PREFIX} INFO: ${TOTAL}件取得, エラー${ERRORS}件"

# CLAUDE.local.md に新着サマリを記録
if [ "${DRY_RUN}" = "0" ] && [ "${TOTAL}" -gt 0 ]; then
    # 同日の既存エントリを削除（冪等性）
    grep -v "tech-feeds ${DATE}" "${LOCAL_MD}" > "${LOCAL_MD}.tmp" && mv "${LOCAL_MD}.tmp" "${LOCAL_MD}" || true

    # 新着サマリを生成して追記
    SUMMARY=$(python3 -c "
import json
with open('${FEEDS_OUTPUT}') as f:
    data = json.load(f)
sources = {}
for e in data['entries']:
    sources.setdefault(e['source'], []).append(e['title'][:50])
parts = []
for src, titles in sources.items():
    parts.append(f'{src}({len(titles)})')
print(', '.join(parts))
")
    echo "- ${DATE} tech-feeds: ${TOTAL}件 — ${SUMMARY}" >> "${LOCAL_MD}"
fi

echo "${LOG_PREFIX} ===== フィード取得完了 ====="
