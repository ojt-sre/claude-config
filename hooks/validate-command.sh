#!/bin/bash
# PreToolUse hook: Bashコマンドの実行前バリデーション

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# 各チェックで block() を呼ぶ
block() { echo "Blocked: $1" >&2; exit 2; }

# --- クォート除去・コマンド分割 ---
# シングル/ダブルクォート内の文字列を除去（URL等に含まれるメタ文字の誤検知を防ぐ）
# エスケープ済みクォート等のエッジケースは安全側（誤検知）に倒す
SANITIZED=$(echo "$COMMAND" | sed "s/'[^']*'//g" | sed 's/"[^"]*"//g')
# シェル演算子（&&, ||, ;, |）で分割してチェック
SUBCMDS=$(echo "$SANITIZED" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g')

# 破壊的コマンド（rm -rf, dd, mkfs, fdisk, parted, shutdown系, crontab -r）
echo "$SUBCMDS" | grep -qE '(^|\s)(rm\s+-r[f]|rm\s+-fr|dd\s+.*of=/dev/|mkfs|fdisk|parted|shutdown|reboot|halt|poweroff|crontab\s+-r)\b' \
  && block "destructive command detected"

# git: force push, global/system config
echo "$SANITIZED" | grep -qE 'git\s+push\s+(--force|-f)\b' && block "git push --force"
echo "$SANITIZED" | grep -qE 'git\s+config\s+(--global|--system)' && block "git config --global/--system"
# git: 変更を消す操作（意図せず実行すると取り返しがつかない）
echo "$SANITIZED" | grep -qE 'git\s+checkout\s+(--theirs|--ours)\b' && block "git checkout --theirs/--ours (discards changes)"
echo "$SANITIZED" | grep -qE 'git\s+clean\s+[^-]*-[a-zA-Z]*f' && block "git clean -f (deletes untracked files)"
echo "$SANITIZED" | grep -qE 'git\s+checkout\s+--\s+\.' && block "git checkout -- . (discards all working tree changes)"
echo "$SANITIZED" | grep -qE 'git\s+restore\s+\.' && block "git restore . (discards all working tree changes)"

# 本番環境への直接アクセス
echo "$SANITIZED" | grep -qiE '(--profile[= ](prod|production)|--context[= ](prod|production)|workspace\s+select\s+(prod|production)|ssh\s+(prod|production)|kubectl.*--context.*(prod|production))' \
  && block "production environment access"

# 秘密情報・認証情報
echo "$SANITIZED" | grep -qE '(cat|less|more|head|tail)\s+.*\.(pem|key|p12|pfx)' && block "reading secret files"
echo "$SANITIZED" | grep -qE 'aws\s+.*--query.*SecretAccessKey|printenv.*AWS_SECRET' && block "exposing AWS credentials"

# パッケージのグローバルインストール
echo "$SANITIZED" | grep -qE '(npm\s+(install|i)\s+(-g|--global)|gem\s+install\s)' && block "global package install"

# GitHub CLI 破壊的操作
echo "$SANITIZED" | grep -qE 'gh\s+(repo|release|pr|issue)\s+delete' && block "gh destructive operation"

# その他の危険パターン
echo "$SANITIZED" | grep -qF ':(){ :|:&' && block "fork bomb"
echo "$SANITIZED" | grep -qE 'chmod\s+.*\+s' && block "chmod +s (setuid/setgid)"
echo "$SANITIZED" | grep -qE 'history\s+-[cw]|>\s*~?\/?(\.bash_history|\.zsh_history)' && block "clearing shell history"

exit 0
