#!/bin/bash
# PermissionRequest hook: 承認回数が閾値を超えたBashパターンを自動昇格
# 完全ブラック: sudo, su → 昇格しない
# 条件付き: bash, sh, rm, chmod → 安全フラグの組み合わせのみ昇格
# 通常: それ以外 → 先頭語で昇格

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

THRESHOLD=3
SETTINGS="$HOME/.claude/settings.json"
LOG="$HOME/.claude/data/bash-approved.log"

# 複数行コマンドは自動昇格しない（settings.json に壊れたルールが入るのを防ぐ）
if echo "$COMMAND" | grep -q $'\n'; then
  exit 0
fi

# 先頭語を抽出
HEAD=$(echo "$COMMAND" | awk '{print $1}')
[[ -z "$HEAD" ]] && exit 0

# --- 完全ブラック ---
BLACKLIST="sudo su"
if echo "$BLACKLIST" | grep -qw "$HEAD"; then
  exit 0
fi

# --- 条件付きブラック ---
CONDITIONAL="bash sh rm chmod"
SAFE_FLAGS="bash:-n sh:-n rm:-i chmod:+x chmod:-x"

if echo "$CONDITIONAL" | grep -qw "$HEAD"; then
  FLAG=$(echo "$COMMAND" | awk '{print $2}')
  [[ -z "$FLAG" ]] && exit 0

  COMBO="${HEAD}:${FLAG}"
  if ! echo "$SAFE_FLAGS" | grep -qw "$COMBO"; then
    exit 0
  fi

  PATTERN="${HEAD} ${FLAG}"
else
  # --- 通常 ---
  PATTERN="$HEAD"
fi

# ログがなければ何もしない
[[ ! -f "$LOG" ]] && exit 0

# 7日以上古いログはリセット（stale な承認パターンの蓄積防止）
if [[ -f "$LOG" ]] && find "$LOG" -mtime +7 -print -quit | grep -q .; then
  rm -f "$LOG"
  exit 0
fi

# 承認回数をカウント
COUNT=$(grep -cxF "$PATTERN" "$LOG" 2>/dev/null || echo 0)

if [[ "$COUNT" -ge "$THRESHOLD" ]]; then
  RULE="Bash(${PATTERN} *)"

  # settings.jsonのallowリストに追加
  TMP=$(mktemp)
  if jq --arg rule "$RULE" '.permissions.allow += [$rule]' "$SETTINGS" > "$TMP" 2>/dev/null; then
    mv "$TMP" "$SETTINGS"
  else
    rm -f "$TMP"
    exit 0
  fi

  # ログから該当パターンを削除
  sed -i "/^$(echo "$PATTERN" | sed 's/[.[\*^$()+?{|]/\\&/g')$/d" "$LOG"

  # 自動承認
  cat <<'EOJSON'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOJSON
fi

exit 0
