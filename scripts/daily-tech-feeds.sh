#!/bin/bash
# daily-tech-feeds.sh
# 毎日8時: 技術フィードを取得し Discord に通知する
#
# cron登録:
#   0 8 * * * ${HOME}/.claude/scripts/daily-tech-feeds.sh >> ${HOME}/.claude/scripts/daily-tech-feeds.log 2>&1

set -euo pipefail

export NVM_DIR="${HOME}/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

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

# Discord 通知（0件のときは「新規なしっス」だけ通知して Obsidian は書かない）
if [ "${DRY_RUN}" = "0" ] && [ "${TOTAL}" = "0" ]; then
    EMPTY_PAYLOAD=$(python3 -c "
import json
payload = {
    'embeds': [{
        'title': '📡 先輩！今日は新規なしっス！',
        'description': '過去7日間のフィードは全部既出だったっス。明日また見ますっス！',
        'color': 10070709,
        'footer': {'text': '${DATE} / 0件取得'}
    }]
}
print(json.dumps(payload))
")
    notify_discord "${DISCORD_WEBHOOK_TECH_FEEDS:-}" "$EMPTY_PAYLOAD"
fi

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
    if rec.get('use_case'):
        lines.append(f\"💡 {rec['use_case']}\")
    lines.append(rec.get('url', ''))
    lines.append('')
rest = [i for i in items if not i.get('recommended')]
for n, item in enumerate(rest, 2):
    lines.append(f\"{n}. **{item['source']}** — {item['title']}\")
    lines.append(item.get('summary_ja', ''))
    if item.get('use_case'):
        lines.append(f\"💡 {item['use_case']}\")
    lines.append(item.get('url', ''))
    lines.append('')
payload = {
    'embeds': [{
        'title': '📡 先輩！今日の最新情報っス！',
        'description': '\n'.join(lines).strip(),
        'color': 3447003,
        'footer': {'text': '${DATE} / ${TOTAL}件取得'}
    }]
}
print(json.dumps(payload))
")
        notify_discord "${DISCORD_WEBHOOK_TECH_FEEDS:-}" "$DISCORD_BODY"
    fi

    # Obsidian 記録
    obsidian_md=$(run_cmd "obsidian-tech-feeds") || {
        echo "${LOG_PREFIX} WARN: Obsidian記事生成失敗。スキップ"
        obsidian_md=""
    }

    if [ -n "$obsidian_md" ]; then
        OBSIDIAN_FILE="/mnt/c/Obsidian/20_最新情報/${DATE} テックニュースまとめ.md"
        # Sonnet が「っス」を「っS」（半角S）で出力する癖があるため、書き出し前にサニタイズする。
        # 「っS」直後は実観測で全て日本語句読点・区切り記号のみで、英単語の一部になるケースはなし（2026-05-20確認）。
        obsidian_md=$(printf '%s' "$obsidian_md" | sed 's/っS/っス/g')
        printf '%s\n' "$obsidian_md" > "$OBSIDIAN_FILE"
        echo "${LOG_PREFIX} INFO: Obsidian記録完了: ${DATE} テックニュースまとめ.md"
    fi

    # ランキングで実際に選ばれた記事のURLだけを seen-urls に追記する。
    # fetch-tech-feeds.py 側では書き込みを行わないため、
    # ここで追記しないと同じ記事が翌日も候補として浮上し続ける。
    # 30日経過したエントリは pruning する。
    if [ -n "$ranked_json" ]; then
        RANKED_JSON="$ranked_json" python3 - <<'PYEOF'
import json
import os
from datetime import datetime, timedelta
from pathlib import Path

SEEN_PATH = Path.home() / ".claude" / "data" / "tech-feeds-seen-urls.json"
EXPIRE_DAYS = 30

ranked = json.loads(os.environ["RANKED_JSON"])
today = datetime.now().strftime("%Y-%m-%d")

seen = {}
if SEEN_PATH.exists():
    seen = json.loads(SEEN_PATH.read_text(encoding="utf-8"))

added = 0
for item in ranked:
    url = item.get("url", "")
    if not url:
        continue
    if url not in seen:
        added += 1
    seen[url] = today

cutoff = (datetime.now() - timedelta(days=EXPIRE_DAYS)).strftime("%Y-%m-%d")
pruned = {u: d for u, d in seen.items() if d >= cutoff}

SEEN_PATH.parent.mkdir(parents=True, exist_ok=True)
SEEN_PATH.write_text(json.dumps(pruned, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"INFO: seen-urls 更新: 新規追加 {added}件, 合計 {len(pruned)}件（pruned前: {len(seen)}件）")
PYEOF
    fi
fi

echo "${LOG_PREFIX} ===== フィード取得完了 ====="
