#!/bin/bash
# test-dispatch-ops.sh
# ~/.claude/scripts/lib.sh の dispatch_ops を多パターンで検証する。
# lib.sh 変更時・cron 回帰の疑いがあるときに手動で回す。
#
# 実行:
#   bash ~/.claude/scripts/tests/test-dispatch-ops.sh

set -uo pipefail

# PROJECT_DIR はテスト用一時領域に向ける（実リポジトリを汚さない）
TEST_DIR=$(mktemp -d)
export PROJECT_DIR="$TEST_DIR"
mkdir -p "$TEST_DIR/r"

# NVM 読み込み（cron 環境と同条件に近づける）
export NVM_DIR="${HOME}/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

source "${HOME}/.claude/scripts/lib.sh"

pass=0; fail=0
check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $name"
        pass=$((pass+1))
    else
        echo "FAIL: $name"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        fail=$((fail+1))
    fi
}

# Case 1: 前置きに [p0] を含む（2026-04-22 実測バグの最小再現）
input1='これは [p0] のアイテムを使った記事です。以下が出力:
[{"op":"write","path":"a.md","content":"hello"}]'
result1=$(dispatch_ops "$input1" 2>&1)
check "case1: preamble [p0]" "write: a.md" "$result1"

# Case 2: 純粋な JSON 配列
input2='[{"op":"write","path":"b.md","content":"x"}]'
result2=$(dispatch_ops "$input2" 2>&1)
check "case2: pure array" "write: b.md" "$result2"

# Case 3: コードフェンス付き
input3='```json
[{"op":"write","path":"c.md","content":"c"}]
```'
result3=$(dispatch_ops "$input3" 2>&1)
check "case3: code fence" "write: c.md" "$result3"

# Case 4: Haiku がオブジェクト単体を返す
input4='{"op":"write","path":"d.md","content":"d"}'
result4=$(dispatch_ops "$input4" 2>&1)
check "case4: object only" "write: d.md" "$result4"

# Case 5: preamble [p0] + 複数 op
input5='選ばれたアイテム: [p0] 2026-04-21: AIが嘘をつく
出力:
[{"op":"write","path":"e.md","content":"e"},{"op":"copy","src":"e.md","dest":"r/e.md"}]'
result5=$(dispatch_ops "$input5" 2>&1)
check "case5: preamble [p0] + 2-op" "$(printf 'write: e.md\ncopy: e.md -> r/e.md')" "$result5"

# Case 6: content 内に [p0] を含む（誤検知しないこと）
input6='[{"op":"write","path":"f.md","content":"本文に [p0] を含む"}]'
result6=$(dispatch_ops "$input6" 2>&1)
check "case6: content contains [p0]" "write: f.md" "$result6"

# Case 7: JSON が無い → エラー + raw 保存
input7='JSONは出力できませんでした'
result7=$(dispatch_ops "$input7" 2>&1 || true)
if echo "$result7" | grep -q "ERROR" && ls "${TEST_DIR}/logs/dispatch-failures/"*.txt >/dev/null 2>&1; then
    echo "PASS: case7: no json → error + raw saved"
    pass=$((pass+1))
else
    echo "FAIL: case7: no json"
    echo "  actual: $result7"
    fail=$((fail+1))
fi

echo ""
echo "=== Results: $pass passed, $fail failed ==="
echo "TEST_DIR: $TEST_DIR（手動確認後に削除してよい）"
exit $fail
