#!/bin/bash
# PermissionRequest hook: Edit/Write を対話セッションで自動承認
# CLAUDE_SUBPROCESS=1 の場合は明示的に deny し、JSON返却を促す

if [ "${CLAUDE_SUBPROCESS:-0}" = "1" ]; then
  cat <<'EOJSON'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"このセッションはサブプロセスモードです。ファイルへの書き込みはシステム側が行います。ツールを使わずJSON配列をテキストとして返してください。"}}}
EOJSON
  exit 0
fi

cat <<'EOJSON'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOJSON
