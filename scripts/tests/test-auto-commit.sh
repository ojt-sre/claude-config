#!/bin/bash
# test-auto-commit.sh
# ~/.claude/scripts/lib.sh の auto_commit / auto_push を検証する。
# 一時 git リポジトリを作って動作を確認する（実リポジトリは触らない）。
#
# 実行:
#   bash ~/.claude/scripts/tests/test-auto-commit.sh

set -uo pipefail

TEST_DIR=$(mktemp -d)
export PROJECT_DIR="$TEST_DIR"
export LOG_PREFIX="[TEST]"

# NVM 読み込み（lib.sh の node チェック通過のため）
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

# 準備: テスト用 git リポジトリ
git -C "$TEST_DIR" init -q -b main
git -C "$TEST_DIR" -c user.email="test@test" -c user.name="test" commit -q --allow-empty -m "init"
# auto_commit が git config の user を要求するので最低限設定する
git -C "$TEST_DIR" config user.email "test@test"
git -C "$TEST_DIR" config user.name "test"

echo "--- Case 1: 単一ファイルを add してコミット ---"
echo "foo" > "$TEST_DIR/a.txt"
auto_commit a.txt -- "feat: add a.txt (自動)" > /tmp/auto_commit_out 2>&1
ec=$?
check "case1: exit code" "0" "$ec"
last_msg=$(git -C "$TEST_DIR" log -1 --pretty=%s)
check "case1: commit message" "feat: add a.txt (自動)" "$last_msg"

echo "--- Case 2: 変更なし → skip（冪等） ---"
auto_commit a.txt -- "feat: nothing (自動)" > /tmp/auto_commit_out 2>&1
ec=$?
check "case2: exit 0 on no changes" "0" "$ec"
if grep -q "変更なし" /tmp/auto_commit_out; then
    check "case2: skip message present" "yes" "yes"
else
    check "case2: skip message present" "yes" "no"
    cat /tmp/auto_commit_out
fi

echo "--- Case 3: 複数ファイルを明示パスで add ---"
echo "1" > "$TEST_DIR/b.txt"
echo "2" > "$TEST_DIR/c.txt"
echo "3" > "$TEST_DIR/d-untracked.txt"  # これは含めない
auto_commit b.txt c.txt -- "chore: add b and c (自動)" > /tmp/auto_commit_out 2>&1
ec=$?
check "case3: exit code" "0" "$ec"
committed=$(git -C "$TEST_DIR" show --name-only --pretty=format: HEAD | tr '\n' ',' | sed 's/,$//' | sed 's/^,//')
check "case3: only b,c staged" "b.txt,c.txt" "$committed"
# d-untracked は残っているはず
if git -C "$TEST_DIR" status --porcelain | grep -q "d-untracked"; then
    check "case3: d-untracked still untracked" "yes" "yes"
else
    check "case3: d-untracked still untracked" "yes" "no"
fi

echo "--- Case 4: DRY_RUN=1 ではコミットしない ---"
echo "dry" > "$TEST_DIR/e.txt"
before_sha=$(git -C "$TEST_DIR" rev-parse HEAD)
DRY_RUN=1 auto_commit e.txt -- "chore: dry (自動)" > /tmp/auto_commit_out 2>&1
ec=$?
after_sha=$(git -C "$TEST_DIR" rev-parse HEAD)
check "case4: exit 0" "0" "$ec"
check "case4: HEAD unchanged" "$before_sha" "$after_sha"

echo "--- Case 5: -- 区切りなし → エラー ---"
auto_commit a.txt "no separator msg" > /tmp/auto_commit_out 2>&1
ec=$?
check "case5: exit 1" "1" "$ec"

echo "--- Case 6: path 指定なし → エラー ---"
auto_commit -- "only message" > /tmp/auto_commit_out 2>&1
ec=$?
check "case6: exit 1" "1" "$ec"

echo "--- Case 7: git リポジトリ外 → エラー ---"
NONGIT=$(mktemp -d)
PROJECT_DIR="$NONGIT" auto_commit x.txt -- "won't work" > /tmp/auto_commit_out 2>&1
ec=$?
check "case7: exit 1 outside git" "1" "$ec"
rm -rf "$NONGIT"

echo "--- Case 8: auto_push DRY_RUN ---"
DRY_RUN=1 auto_push > /tmp/auto_commit_out 2>&1
ec=$?
check "case8: auto_push DRY_RUN exit 0" "0" "$ec"

echo
echo "===== Result: PASS=${pass} FAIL=${fail} ====="
rm -rf "$TEST_DIR"
[ $fail -eq 0 ]
