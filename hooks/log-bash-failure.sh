#!/bin/bash
# PostToolUse hook: Bash失敗を known-failures-staging.log に記録

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

if [[ "$TOOL" != "Bash" ]]; then
  exit 0
fi

EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // empty' 2>/dev/null)

# exit_code が取れない場合は output/error の内容でフォールバック判定
if [[ -z "$EXIT_CODE" ]]; then
  ERROR=$(echo "$INPUT" | jq -r '.tool_response.error // empty' 2>/dev/null)
  [[ -z "$ERROR" ]] && exit 0
  EXIT_CODE="?"
fi

[[ "$EXIT_CODE" == "0" ]] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_response.output // empty' 2>/dev/null | tail -n 20)
DATE=$(date '+%Y-%m-%d %H:%M:%S')
STAGING="$HOME/.claude/known-failures-staging.log"

{
  echo "[$DATE] exit:${EXIT_CODE}"
  echo "CMD: $COMMAND"
  echo "OUT: $OUTPUT"
  echo "---"
} >> "$STAGING"

exit 0
