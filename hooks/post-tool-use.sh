#!/bin/bash
# PostToolUse hook: .tfファイル編集後にterraform fmt を自動実行

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Edit/Writeツールで.tfファイルが変更された場合のみ実行
if [[ "$TOOL" != "Edit" && "$TOOL" != "Write" ]]; then
  exit 0
fi

if [[ "$FILE" != *.tf ]]; then
  exit 0
fi

if command -v terraform &>/dev/null; then
  terraform fmt "$FILE" 2>/dev/null || true
fi

exit 0
