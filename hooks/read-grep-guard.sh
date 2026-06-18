#!/bin/bash
# PreToolUse hook (Read|Grep): /mnt/c 配下を Read/Grep tool で読むのを止め、
# CR汚染しない代替（mcat / tr -d '\r'）へ誘導する。
#
# 理由: /mnt/c は Windows・CRLF。Read/Grep tool の複数行出力が行末 \r で崩れ
#       （カーソルが列0に戻り後続を上書き）、その崩れが私のコンテキストにも
#       入って応答が壊れる（known-failures.md 参照。2026-06-18 case-close 中断の実害）。
#       「読むとき手で tr -d '\r'」は忘れた瞬間崩れるので、hook で強制する。
# 対象外: Edit/Write はファイル実体に作用し表示崩れの影響を受けないので止めない。

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Read は file_path、Grep は path をターゲットとして見る
case "$TOOL" in
  Read) RAW=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) ;;
  Grep) RAW=$(echo "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null) ;;
  *) exit 0 ;;
esac
[ -z "$RAW" ] && exit 0   # Grep の path 省略時は cwd(=LF) なので素通し

# ~ 展開 + シンボリックリンク解決（~/obsidian_vault → /mnt/c/Obsidian の裏口も捕捉）
EXPANDED="${RAW/#\~/$HOME}"
RESOLVED=$(realpath -m "$EXPANDED" 2>/dev/null || echo "$EXPANDED")

case "$RESOLVED" in
  /mnt/c|/mnt/c/*)
    if [ "$TOOL" = "Read" ]; then
      echo "Blocked: /mnt/c は CRLF。Read tool だと出力が崩れる。代わりに Bash で: mcat -n '$RAW' （行番号付き）。grep したいなら mcat '$RAW' | grep -n PATTERN" >&2
    else
      echo "Blocked: /mnt/c は CRLF。Grep tool だと出力が崩れる。代わりに Bash で: grep -rn PATTERN '$RAW' | tr -d '\r'" >&2
    fi
    exit 2
    ;;
esac
exit 0
