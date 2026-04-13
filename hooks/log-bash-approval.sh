#!/bin/bash
# PostToolUse hook: 承認されたBashコマンドのパターンをログに記録
# 既にallowリストにあるコマンドは記録しない（手動承認のみ対象）

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL" != "Bash" ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# 先頭語を抽出
PATTERN=$(echo "$COMMAND" | awk '{print $1}')
[[ -z "$PATTERN" ]] && exit 0

# 条件付きブラック: 先頭語+第一フラグをパターンにする
CONDITIONAL="bash sh rm chmod"
if echo "$CONDITIONAL" | grep -qw "$PATTERN"; then
  FLAG=$(echo "$COMMAND" | awk '{print $2}')
  [[ -z "$FLAG" ]] && exit 0
  PATTERN="${PATTERN} ${FLAG}"
fi

# 既にallowリストに存在するか確認
SETTINGS="$HOME/.claude/settings.json"
ESCAPED=$(echo "$PATTERN" | sed 's/[.[\*^$()+?{|]/\\&/g')
if grep -q "\"Bash(${ESCAPED} " "$SETTINGS" 2>/dev/null; then
  exit 0
fi

# ログに記録
DATA_DIR="$HOME/.claude/data"
mkdir -p "$DATA_DIR"
echo "$PATTERN" >> "$DATA_DIR/bash-approved.log"

exit 0
