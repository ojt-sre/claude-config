#!/bin/bash
# SessionStart hook: CLAUDE.local.md の読み込みと staging log の通知

# settings.json の JSON 構文チェック
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ]; then
  if ! python3 -m json.tool "$SETTINGS" > /dev/null 2>&1; then
    echo "⚠️  settings.json が壊れています。セッション設定がスキップされています。"
    echo "   修正してください: $SETTINGS"
  fi
fi

# カレントディレクトリの CLAUDE.local.md を読む
# /mnt/c/ 配下のパスは Windows パスに変換して確認
LOCAL_MD=""
if [ -f "$PWD/CLAUDE.local.md" ]; then
  LOCAL_MD="$PWD/CLAUDE.local.md"
fi

if [ -n "$LOCAL_MD" ]; then
  cat "$LOCAL_MD"
fi

# known-failures-staging.log にエントリがあれば通知
STAGING="$HOME/.claude/known-failures-staging.log"
if [ -s "$STAGING" ]; then
  ENTRY_COUNT=$(grep -c '^---$' "$STAGING" 2>/dev/null) || ENTRY_COUNT="?"
  echo ""
  echo "⚠️  known-failures-staging.log に ${ENTRY_COUNT} 件の失敗ログがあります。"
  echo "   内容を確認して known-failures.md への昇格を検討してください: ~/.claude/known-failures-staging.log"
fi

exit 0
