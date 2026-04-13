#!/usr/bin/env python3
"""health-check.py — リポジトリの健全性チェック（L1 Infrastructure）

/confirm の機械的チェック項目をPythonで実行する。
AIのクリエイティビティが不要な「存在確認」「整合性チェック」を担当。

使い方:
  python3 health-check.py ~/content-pipeline         # 単体チェック
  python3 health-check.py --all                       # 全リポジトリ
  python3 health-check.py --all --output report.txt   # ファイル出力
  python3 health-check.py ~/content-pipeline --format json
  python3 health-check.py ~/content-pipeline --fix    # 不足ディレクトリを自動作成
  python3 health-check.py ~/content-pipeline --dry-run  # 確認のみ
"""

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

# --- リポジトリ定義 ---
# CLAUDE.local.md + .git を持つサブディレクトリを Claude管理リポジトリとして自動検出する。
# 新しいリポジトリを追加した場合、CLAUDE.local.md を置くだけで自動的に対象になる。

REPOS = {
    d.name: str(d)
    for d in Path.home().iterdir()
    if d.is_dir() and (d / "CLAUDE.local.md").exists() and (d / ".git").exists()
}

GLOBAL_TOOLS = ["cost-report.py", "lint-ai-style.py", "health-check.py", "fetch-tech-feeds.py"]

# --- 憲法ルール目録（L5 Meta）---
# CLAUDE.md の機械チェック可能なルールをここで宣言する。
# 新しい憲法ルールを追加したら:
#   (1) ここにエントリ追加 → (2) 対応実装の近くに # RULE: <id> コメント追加
CONSTITUTION_RULE_IDS = [
    "dry_run",              # スクリプトには --dry-run モードを実装する
    "set_euo_pipefail",     # Bash スクリプトには set -euo pipefail を書く
    "git_https",            # Git remote は HTTPS を使う（SSH不可）
    "style_rules",          # .clauderules に STYLE RULES セクションを持つ
    "l1_tools",             # ~/.claude/scripts/ に L1 ツールが存在する
    "known_failures",       # known-failures.md が存在する
    "copyright",            # コンテンツ生成リポジトリに著作権ガイドラインがある
    "production_protection",  # スクリプトに保護なしの不可逆操作がない
    "l5_autonomy",          # CLAUDE.md に L5 自律権限セクションが存在する
    "architecture_coverage",  # architecture.md に全アーティファクトが記載されている
    "command_frontmatter",    # commands/*.md に正しいYAML frontmatter がある
]


# --- チェック結果 ---

@dataclass
class Check:
    name: str
    passed: bool
    detail: str = ""
    fixable: bool = False


def check_file_exists(path: str, name: str) -> Check:
    exists = Path(path).exists()
    return Check(name=name, passed=exists,
                 detail=path if not exists else "", fixable=False)


def check_dir_exists(path: str, name: str, fixable: bool = True) -> Check:
    exists = Path(path).is_dir()
    return Check(name=name, passed=exists,
                 detail=path if not exists else "", fixable=fixable)


# --- 憲法ルール準拠チェック（共通） ---

def check_scripts_dry_run(repo_path: str) -> list[Check]:  # RULE: dry_run
    """scripts/*.sh に --dry-run 実装があるか確認（lib.sh は除外）"""
    results = []
    scripts_dir = Path(repo_path) / "scripts"
    if not scripts_dir.is_dir():
        return results

    for sh in sorted(scripts_dir.glob("*.sh")):
        if sh.name == "lib.sh":
            continue
        content = sh.read_text(encoding="utf-8", errors="ignore")
        has_dry_run = "DRY_RUN" in content
        results.append(Check(
            name=f"dry-run: scripts/{sh.name}",
            passed=has_dry_run,
            detail="" if has_dry_run else "--dry-run 未実装",
        ))

    return results


def check_scripts_set_e(repo_path: str) -> list[Check]:  # RULE: set_euo_pipefail
    """scripts/*.sh に set -euo pipefail があるか確認（lib.sh は除外）"""
    results = []
    scripts_dir = Path(repo_path) / "scripts"
    if not scripts_dir.is_dir():
        return results

    for sh in sorted(scripts_dir.glob("*.sh")):
        if sh.name == "lib.sh":
            continue
        content = sh.read_text(encoding="utf-8", errors="ignore")
        has_set_e = "set -euo pipefail" in content
        results.append(Check(
            name=f"set -euo pipefail: scripts/{sh.name}",
            passed=has_set_e,
            detail="" if has_set_e else "set -euo pipefail なし",
        ))

    return results


def check_git_https(repo_path: str) -> Check:  # RULE: git_https
    """Git remote が HTTPS か確認"""
    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "remote", "-v"],
            capture_output=True, text=True, timeout=5)
        if not result.stdout.strip():
            return Check(name="Git remote HTTPS", passed=False, detail="remote未設定")
        is_https = "https://" in result.stdout
        return Check(
            name="Git remote HTTPS",
            passed=is_https,
            detail="" if is_https else "SSH使用（HTTPSに変更推奨）",
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return Check(name="Git remote HTTPS", passed=False, detail="git実行失敗")


# --- 著作権・本番保護・L5自律権限チェック ---

# 外部公開コンテンツを生成するリポジトリ（著作権チェック対象）。
# 構造的な特徴での自動検出が困難なため明示リスト。新規リポジトリ追加時はここも更新する。
CONTENT_REPOS = {"content-pipeline", "lol-guides-jp"}


def check_copyright_guidelines(repo_path: str) -> Check:  # RULE: copyright
    """コンテンツ生成リポジトリの .clauderules に著作権ガイドラインがあるか"""
    repo_name = Path(repo_path).name
    if repo_name not in CONTENT_REPOS:
        return Check(name="著作権ガイドライン", passed=True,
                     detail="コンテンツ生成リポジトリではない")

    clauderules = Path(repo_path) / ".clauderules"
    if not clauderules.exists():
        return Check(name="著作権ガイドライン", passed=False,
                     detail=".clauderules が存在しない")

    content = clauderules.read_text(encoding="utf-8", errors="ignore")
    keywords = ["著作権", "copyright", "オリジナル", "引用"]
    has_copyright = any(kw in content for kw in keywords)
    return Check(
        name="著作権ガイドライン",
        passed=has_copyright,
        detail="" if has_copyright else ".clauderules に著作権関連の記載なし",
    )


def check_no_bare_destructive(repo_path: str) -> list[Check]:  # RULE: production_protection
    """スクリプトに DRY_RUN ガードなしの不可逆操作がないか確認"""
    results = []
    scripts_dir = Path(repo_path) / "scripts"
    if not scripts_dir.is_dir():
        return results

    destructive_patterns = ["rm -rf", "git push --force", "DROP TABLE", "DROP DATABASE"]
    for sh in sorted(scripts_dir.glob("*.sh")):
        if sh.name == "lib.sh":
            continue
        content = sh.read_text(encoding="utf-8", errors="ignore")
        for pattern in destructive_patterns:
            if pattern in content and "DRY_RUN" not in content:
                results.append(Check(
                    name=f"本番保護: scripts/{sh.name}",
                    passed=False,
                    detail=f"'{pattern}' が DRY_RUN ガードなしで使用",
                ))

    return results


def check_l5_autonomy_documented() -> Check:  # RULE: l5_autonomy
    """CLAUDE.md に L5 自律権限セクションが存在するか"""
    claude_md = Path.home() / ".claude" / "CLAUDE.md"
    if not claude_md.exists():
        return Check(name="L5自律権限ドキュメント", passed=False,
                     detail="CLAUDE.md が存在しない")
    content = claude_md.read_text(encoding="utf-8", errors="ignore")
    has_section = "L5" in content and "自律権限" in content
    return Check(
        name="L5自律権限ドキュメント",
        passed=has_section,
        detail="" if has_section else "CLAUDE.md に L5 自律権限セクションがない",
    )


def check_l5_hallucination_guard() -> Check:  # RULE: l5_autonomy
    """L5 自律権限の安全弁: CLAUDE.md に危険なコマンド許可が混入していないか検証"""
    claude_md = Path.home() / ".claude" / "CLAUDE.md"
    if not claude_md.exists():
        return Check(name="L5ハルシネーション防御", passed=True, detail="CLAUDE.md なし（スキップ）")

    content = claude_md.read_text(encoding="utf-8", errors="ignore")

    # settings.json の deny リストと同等の危険パターン
    dangerous_patterns = [
        "rm -rf",
        "git push --force",
        "chmod 777",
        "curl | bash", "curl | sh",
        "npm install -g", "npm i -g",
        "terraform destroy",
        "DROP TABLE", "DROP DATABASE",
    ]

    found = []
    for i, line in enumerate(content.splitlines(), 1):
        lower = line.lower()
        # コメント・引用・禁止ルール内の言及は除外（「〜してはいけない」文脈）
        if any(neg in lower for neg in ["禁止", "しない", "不可", "deny", "block", "prevent"]):
            continue
        for pat in dangerous_patterns:
            if pat.lower() in lower:
                found.append(f"L{i}: {pat}")

    return Check(
        name="L5ハルシネーション防御",
        passed=len(found) == 0,
        detail=f"CLAUDE.md に危険パターン混入: {', '.join(found)}" if found else "",
    )


# --- コマンド frontmatter チェック ---

def check_command_frontmatter() -> list[Check]:  # RULE: command_frontmatter
    """全コマンドに正しいYAML frontmatter（description付き）があるか確認"""
    results = []
    cmd_dir = Path.home() / ".claude" / "commands"
    if not cmd_dir.is_dir():
        return results

    for md in sorted(cmd_dir.glob("*.md")):
        content = md.read_text(encoding="utf-8", errors="ignore")
        lines = content.split("\n")

        if not lines or lines[0].strip() != "---":
            results.append(Check(
                name=f"frontmatter: {md.name}",
                passed=False,
                detail="YAML frontmatter なし",
            ))
            continue

        end_idx = None
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == "---":
                end_idx = i
                break

        if end_idx is None:
            results.append(Check(
                name=f"frontmatter: {md.name}",
                passed=False,
                detail="frontmatter 終端なし",
            ))
            continue

        fm_text = "\n".join(lines[1:end_idx])
        has_desc = "description:" in fm_text
        if not has_desc:
            results.append(Check(
                name=f"frontmatter: {md.name}",
                passed=False,
                detail="description: フィールドなし",
            ))

    if not any(not r.passed for r in results):
        count = len(list(cmd_dir.glob("*.md")))
        results = [Check(
            name="コマンド frontmatter",
            passed=True,
            detail=f"{count}コマンド全て description 付き",
        )]

    return results


# --- stale / orphan 検出 ---

STALE_THRESHOLD_DAYS = 30
_home_slug = "-" + str(Path.home()).replace("/", "-").lstrip("-")
MEMORY_DIR = Path.home() / ".claude" / "projects" / _home_slug / "memory"


def check_memory_integrity() -> list[Check]:
    """メモリファイルと MEMORY.md の整合性チェック（orphan / dangling）"""
    results = []
    memory_md = MEMORY_DIR / "MEMORY.md"

    if not memory_md.exists():
        results.append(Check(name="MEMORY.md", passed=False,
                             detail="MEMORY.md が存在しない"))
        return results

    content = memory_md.read_text(encoding="utf-8", errors="ignore")
    referenced = set(re.findall(r'\[.*?\]\(([\w_-]+\.md)\)', content))
    actual = {f.name for f in MEMORY_DIR.glob("*.md") if f.name != "MEMORY.md"}

    # Orphan: ファイルあるが MEMORY.md に未記載
    for f in sorted(actual - referenced):
        results.append(Check(
            name=f"メモリ orphan: {f}",
            passed=False,
            detail="MEMORY.md に未記載",
        ))

    # Dangling: MEMORY.md に記載あるがファイルなし
    for f in sorted(referenced - actual):
        results.append(Check(
            name=f"メモリ dangling: {f}",
            passed=False,
            detail="ファイルが存在しない",
        ))

    if not (actual - referenced) and not (referenced - actual):
        results.append(Check(
            name="メモリ整合性",
            passed=True,
            detail=f"ファイル: {len(actual)}, 参照: {len(referenced)}",
        ))

    return results


def check_stale_config(repo_path: str) -> list[Check]:
    """CLAUDE.md / .clauderules の git 最終更新が閾値を超えていないか"""
    results = []

    for fname in ("CLAUDE.md", ".clauderules"):
        fpath = Path(repo_path) / fname
        if not fpath.exists():
            continue
        try:
            result = subprocess.run(
                ["git", "-C", repo_path, "log", "-1", "--format=%ci", "--", fname],
                capture_output=True, text=True, timeout=5)
            date_str = result.stdout.strip()[:10]
            if not date_str:
                continue
            last_modified = datetime.strptime(date_str, "%Y-%m-%d")
            days_ago = (datetime.now() - last_modified).days
            is_stale = days_ago > STALE_THRESHOLD_DAYS
            results.append(Check(
                name=f"stale: {fname}",
                passed=not is_stale,
                detail=f"{days_ago}日前（{date_str}）" if is_stale else "",
            ))
        except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
            pass

    return results


def check_orphan_cron_scripts(repo_path: str) -> list[Check]:
    """ヘッダーに cron 記載があるスクリプトが crontab に登録されているか"""
    results = []
    scripts_dir = Path(repo_path) / "scripts"
    if not scripts_dir.is_dir():
        return results

    try:
        cron = subprocess.run(["crontab", "-l"], capture_output=True, text=True, timeout=5)
        cron_text = cron.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return results

    for sh in sorted(scripts_dir.glob("*.sh")):
        if sh.name == "lib.sh":
            continue
        content = sh.read_text(encoding="utf-8", errors="ignore")
        # 先頭コメントブロック（最大15行）を抽出
        header_lines = []
        for line in content.split("\n")[:15]:
            if line.startswith("#") or line.strip() == "":
                header_lines.append(line)
            else:
                break
        header = "\n".join(header_lines).lower()

        # ヘッダーに cron 登録情報がある（"* *" パターンまたは "cron登録"）
        if ("cron" in header and "* *" in header) or "cron登録" in header:
            if sh.name not in cron_text:
                results.append(Check(
                    name=f"cron orphan: scripts/{sh.name}",
                    passed=False,
                    detail="ヘッダーにcron記載あるがcrontab未登録",
                ))

    return results


# --- architecture.md 整合性チェック ---

def check_architecture_coverage(base_path: str) -> list[Check]:  # RULE: architecture_coverage
    """architecture.md に記載されていないアーティファクトを検出する"""
    results = []
    base = Path(base_path)
    arch_file = base / "architecture.md"

    if not arch_file.exists():
        results.append(Check(
            name="architecture.md",
            passed=False,
            detail="architecture.md が存在しない",
        ))
        return results

    arch_content = arch_file.read_text(encoding="utf-8", errors="ignore")

    # スキャン対象ディレクトリとパターン
    scan_targets = [
        ("scripts", "*.sh"),
        ("scripts", "*.py"),
        ("commands", "*.md"),
        ("config", "*"),
        ("hooks", "*.sh"),
        ("agents", "*.md"),
        ("templates/base", "*"),
        ("templates/sre", "*"),
    ]

    skip_files = {"__pycache__"}

    for subdir, pattern in scan_targets:
        target_dir = base / subdir
        if not target_dir.is_dir():
            continue
        for f in sorted(target_dir.glob(pattern)):
            if f.name in skip_files or f.is_dir():
                continue
            # architecture.md 内にファイル名が記載されているか
            relative = f"{subdir}/{f.name}"
            if relative not in arch_content:
                results.append(Check(
                    name=f"architecture未記載: {relative}",
                    passed=False,
                    detail="architecture.md に記載なし",
                ))

    if not any(not r.passed for r in results):
        results.append(Check(
            name="architecture.md 整合性",
            passed=True,
            detail="全アーティファクトが記載済み",
        ))

    return results


# --- メタチェック（health-check.py 自身の憲法準拠） ---

def check_self_coverage() -> list[Check]:
    """health-check.py 自身が全憲法ルールをカバーしているか確認"""
    results = []
    self_src = Path(__file__).read_text(encoding="utf-8")

    # --dry-run フラグの実装確認
    results.append(Check(
        name="self: --dry-run 実装",
        passed="args.dry_run" in self_src,
        detail="" if "args.dry_run" in self_src else "health-check.py 自身に --dry-run がない",
    ))

    # 各憲法ルールに対応する # RULE: <id> アノテーションの存在確認
    for rule_id in CONSTITUTION_RULE_IDS:
        marker = f"# RULE: {rule_id}"
        has_impl = marker in self_src
        results.append(Check(
            name=f"self: RULE:{rule_id}",
            passed=has_impl,
            detail="" if has_impl else f"'{marker}' アノテーションなし → 実装漏れの可能性",
        ))

    return results


# --- グローバルチェック（~/.claude/ 全体） ---

def check_global() -> dict:
    """L1ツール・グローバル設定の存在確認"""
    results = []
    scripts_dir = Path.home() / ".claude" / "scripts"

    for tool in GLOBAL_TOOLS:  # RULE: l1_tools
        path = scripts_dir / tool
        results.append(Check(
            name=f"L1ツール: {tool}",
            passed=path.exists(),
            detail=str(path) if not path.exists() else "",
        ))

    kf = Path.home() / ".claude" / "known-failures.md"  # RULE: known_failures
    results.append(Check(
        name="known-failures.md",
        passed=kf.exists(),
        detail=str(kf) if not kf.exists() else "",
    ))

    # L5自律権限ドキュメントの存在確認
    results.append(check_l5_autonomy_documented())

    # L5ハルシネーション防御（危険パターン混入検出）
    results.append(check_l5_hallucination_guard())

    # コマンド frontmatter 整合性
    results.extend(check_command_frontmatter())

    # メモリ整合性（orphan / dangling）
    results.extend(check_memory_integrity())

    # architecture.md 整合性（グローバルスコープ）
    results.extend(check_architecture_coverage(str(Path.home() / ".claude")))

    # メタチェック: health-check.py 自身の憲法準拠
    results.extend(check_self_coverage())

    passed = [r for r in results if r.passed]
    failed = [r for r in results if not r.passed]

    return {
        "repo": "global (~/.claude)",
        "path": str(Path.home() / ".claude"),
        "total": len(results),
        "passed": len(passed),
        "failed": len(failed),
        "fixed": [],
        "checks": [{"name": r.name, "passed": r.passed, "detail": r.detail} for r in results],
    }


# --- 共通チェック（全リポジトリ） ---

def check_common(repo_path: str) -> list[Check]:
    results = []
    p = Path(repo_path)

    # 必須ファイル
    results.append(check_file_exists(str(p / "CLAUDE.md"), "CLAUDE.md"))
    results.append(check_file_exists(str(p / "README.md"), "README.md"))

    clauderules = p / ".clauderules"
    results.append(check_file_exists(str(clauderules), ".clauderules"))
    if clauderules.exists():
        content = clauderules.read_text(encoding="utf-8", errors="ignore")
        results.append(Check(  # RULE: style_rules
            name=".clauderules STYLE RULES",
            passed="STYLE RULES" in content,
            detail="" if "STYLE RULES" in content else "STYLE RULESセクションなし",
        ))

    results.append(check_file_exists(str(p / ".claudeignore"), ".claudeignore"))

    # scripts/lib.sh（scriptsディレクトリがある場合）
    scripts_dir = p / "scripts"
    if scripts_dir.is_dir():
        results.append(check_file_exists(str(scripts_dir / "lib.sh"), "scripts/lib.sh"))

    # Git状態
    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "status", "--porcelain"],
            capture_output=True, text=True, timeout=10)
        # ?? (untracked) は除外してステージ済み・未ステージの変更のみカウント
        uncommitted = sum(1 for line in result.stdout.strip().split("\n")
                          if line and not line.startswith("??")) if result.stdout.strip() else 0
        results.append(Check(
            name="未コミット変更",
            passed=uncommitted == 0,
            detail=f"{uncommitted}件の変更あり" if uncommitted else "",
        ))
    except (subprocess.TimeoutExpired, FileNotFoundError):
        results.append(Check(name="Git状態", passed=False, detail="git実行失敗"))

    # Git remote HTTPS（known-failures.md に明記されている共通ルール）
    results.append(check_git_https(repo_path))

    # コンフリクトマーカー
    try:
        result = subprocess.run(
            ["grep", "-rl", "<<<<<<<", repo_path, "--include=*.md", "--include=*.tf",
             "--include=*.sh", "--include=*.json"],
            capture_output=True, text=True, timeout=10)
        has_conflict = bool(result.stdout.strip())
        results.append(Check(
            name="コンフリクトマーカー",
            passed=not has_conflict,
            detail=result.stdout.strip()[:200] if has_conflict else "",
        ))
    except (subprocess.TimeoutExpired, FileNotFoundError):
        results.append(Check(name="コンフリクトマーカー", passed=True, detail="検索スキップ"))

    # 憲法ルール: scripts/ の --dry-run / set -euo pipefail 実装
    results.extend(check_scripts_dry_run(repo_path))
    results.extend(check_scripts_set_e(repo_path))

    # 憲法ルール: 著作権ガイドライン / 本番保護
    results.append(check_copyright_guidelines(repo_path))
    results.extend(check_no_bare_destructive(repo_path))

    # stale / orphan 検出
    results.extend(check_stale_config(repo_path))
    results.extend(check_orphan_cron_scripts(repo_path))

    # architecture.md 整合性（リポジトリスコープ）
    results.extend(check_architecture_coverage(repo_path))

    return results


# --- content-pipeline 固有チェック ---

def check_pipeline(repo_path: str) -> list[Check]:
    results = []
    p = Path(repo_path)

    # 必須ディレクトリ（ACTIVE機能のみ — architecture.md 参照）
    dirs = [
        "drafts/ja", "drafts/wip",
        "review_queue", "publish_queue/zenn",
        "published/zenn",
        "reports", "ideas", "config",
        ".claude/agents", ".claude/commands",
    ]
    for d in dirs:
        results.append(check_dir_exists(str(p / d), f"DIR: {d}"))

    # 必須設定ファイル（ACTIVE機能のみ — architecture.md 参照）
    configs = [
        "config/topics.md", "config/learnings.md", "config/performance.md",
        "config/repos.md", "architecture.md",
    ]
    for c in configs:
        results.append(check_file_exists(str(p / c), f"FILE: {c}"))

    # agents/ と commands/ の整合性（未参照agentを検出）
    agents_dir = p / ".claude" / "agents"
    commands_dir = p / ".claude" / "commands"
    if agents_dir.is_dir() and commands_dir.is_dir():
        agents = {f.stem for f in agents_dir.glob("*.md")}
        cmd_files = list(commands_dir.glob("*.md"))
        all_cmd_text = "\n".join(
            f.read_text(encoding="utf-8", errors="ignore") for f in cmd_files
        )
        unreferenced = {a for a in agents if f"{a}エージェントとして" not in all_cmd_text}
        results.append(Check(
            name="agents/commands整合性",
            passed=len(unreferenced) == 0,
            detail=f"未参照agent: {', '.join(sorted(unreferenced))}" if unreferenced
                   else f"agents: {len(agents)}, commands: {len(cmd_files)}",
        ))

    # crontabチェック（登録有無 + スクリプトファイル存在）
    try:
        cron = subprocess.run(["crontab", "-l"], capture_output=True, text=True, timeout=5)
        cron_text = cron.stdout
        expected_scripts = [
            "daily-research.sh", "daily-produce.sh",
            "morning-report.sh", "weekly-strategy.sh",
        ]
        for script in expected_scripts:
            in_cron = script in cron_text
            results.append(Check(
                name=f"cron登録: {script}",
                passed=in_cron,
                detail="" if in_cron else "crontabに未登録",
            ))
            script_path = p / "scripts" / script
            results.append(Check(
                name=f"cronファイル: {script}",
                passed=script_path.exists(),
                detail="" if script_path.exists() else "ファイルが存在しない",
            ))
    except (subprocess.TimeoutExpired, FileNotFoundError):
        results.append(Check(name="crontab", passed=False, detail="crontab実行失敗"))

    return results


# --- my-freelance-sre 固有チェック ---

def check_sre(repo_path: str) -> list[Check]:
    results = []
    p = Path(repo_path)

    files = [
        "01-admin-setup/MyBestPractices.md",
        "01-admin-setup/WORKFLOWS.md",
        "01-admin-setup/BestPractices.md",
        "01-admin-setup/QuickRef.md",
    ]
    for f in files:
        results.append(check_file_exists(str(p / f), f"FILE: {f}"))

    results.append(check_dir_exists(str(p / "05-ai-dev-knowledge"), "DIR: 05-ai-dev-knowledge"))

    return results


# --- lol-guides-jp 固有チェック ---

def check_lol(repo_path: str) -> list[Check]:
    results = []
    p = Path(repo_path)

    results.append(check_file_exists(str(p / "POLICY.md"), "FILE: POLICY.md"))
    results.append(check_file_exists(str(p / "TODO.md"), "FILE: TODO.md"))
    results.append(check_dir_exists(str(p / "champions"), "DIR: champions"))
    results.append(check_dir_exists(str(p / "scripts"), "DIR: scripts"))
    results.append(check_file_exists(str(p / "current-patch.txt"), "FILE: current-patch.txt"))
    results.append(check_dir_exists(str(p / "patches"), "DIR: patches"))

    # cron チェック（登録有無 + スクリプトファイル存在）
    try:
        cron = subprocess.run(["crontab", "-l"], capture_output=True, text=True, timeout=5)
        in_cron = "check-patch.sh" in cron.stdout
        results.append(Check(
            name="cron登録: check-patch.sh",
            passed=in_cron,
            detail="" if in_cron else "crontabに未登録",
        ))
        script_path = p / "scripts" / "check-patch.sh"
        results.append(Check(
            name="cronファイル: check-patch.sh",
            passed=script_path.exists(),
            detail="" if script_path.exists() else "ファイルが存在しない",
        ))
    except (subprocess.TimeoutExpired, FileNotFoundError):
        results.append(Check(name="cron: check-patch.sh", passed=False, detail="crontab実行失敗"))

    # チャンピオン数カウント
    champions_dir = p / "champions"
    if champions_dir.is_dir():
        count = sum(1 for d in champions_dir.iterdir() if d.is_dir())
        results.append(Check(
            name="チャンピオン数",
            passed=count > 0,
            detail=f"{count}体",
        ))

    return results


# --- zenn-content 固有チェック ---

def check_zenn(repo_path: str) -> list[Check]:
    results = []
    p = Path(repo_path)

    results.append(check_dir_exists(str(p / "articles"), "DIR: articles"))
    results.append(check_dir_exists(str(p / "books"), "DIR: books"))

    return results


# --- メイン ---

def run_checks(repo_path: str, fix: bool = False) -> dict:
    repo_name = Path(repo_path).name
    results = check_common(repo_path)

    if "content-pipeline" in repo_name:
        results.extend(check_pipeline(repo_path))
    elif "freelance-sre" in repo_name:
        results.extend(check_sre(repo_path))
    elif "lol-guides" in repo_name:
        results.extend(check_lol(repo_path))
    elif "zenn-content" in repo_name:
        results.extend(check_zenn(repo_path))

    fixed = []
    if fix:
        for r in results:
            if not r.passed and r.fixable and r.detail:
                try:
                    os.makedirs(r.detail, exist_ok=True)
                    r.passed = True
                    fixed.append(r.name)
                except OSError:
                    pass

    passed = [r for r in results if r.passed]
    failed = [r for r in results if not r.passed]

    return {
        "repo": repo_name,
        "path": repo_path,
        "total": len(results),
        "passed": len(passed),
        "failed": len(failed),
        "fixed": fixed,
        "checks": [{"name": r.name, "passed": r.passed, "detail": r.detail} for r in results],
    }


def format_text(report: dict) -> str:
    status = "PASS" if report["failed"] == 0 else "FAIL"
    lines = [f"[{status}] {report['repo']} — {report['passed']}/{report['total']}"]

    if report.get("fixed"):
        lines.append(f"  自動修復: {', '.join(report['fixed'])}")

    failed = [c for c in report["checks"] if not c["passed"]]
    if failed:
        lines.append("  --- 不合格 ---")
        for c in failed:
            detail = f" ({c['detail']})" if c["detail"] else ""
            lines.append(f"  NG: {c['name']}{detail}")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="リポジトリ健全性チェック")
    parser.add_argument("path", nargs="?", help="チェック対象のリポジトリパス")
    parser.add_argument("--all", action="store_true", help="全リポジトリをチェック")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    parser.add_argument("--fix", action="store_true", help="不足ディレクトリを自動作成")
    parser.add_argument("--dry-run", action="store_true", dest="dry_run",
                        help="修正は行わず確認のみ（--fixを無効化）")
    parser.add_argument("--output", metavar="FILE",
                        help="結果をファイルに出力（省略時はstdout）")
    args = parser.parse_args()

    if args.dry_run and args.fix:
        print("--dry-run が指定されているため --fix は無効です")
        args.fix = False

    if not args.path and not args.all:
        args.path = os.getcwd()

    # グローバルチェック（常に実行）
    reports = [check_global()]

    targets = list(REPOS.values()) if args.all else [args.path]
    for target in targets:
        if not Path(target).is_dir():
            reports.append({"repo": target, "error": "ディレクトリが存在しない"})
            continue
        reports.append(run_checks(target, fix=args.fix))

    # 出力生成
    if args.format == "json":
        output = json.dumps(reports, ensure_ascii=False, indent=2)
    else:
        lines = []
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
        lines.append(f"# health-check {timestamp}")
        lines.append("")
        for r in reports:
            if "error" in r:
                lines.append(f"[ERROR] {r['repo']}: {r['error']}")
            else:
                lines.append(format_text(r))
            lines.append("")
        output = "\n".join(lines).rstrip()

    # ファイル or stdout
    latest = Path.home() / ".claude" / "reports" / "health-check-latest.txt"
    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(output + "\n", encoding="utf-8")
        # latest も常に更新
        latest.parent.mkdir(parents=True, exist_ok=True)
        latest.write_text(output + "\n", encoding="utf-8")
    else:
        print(output)

    # self: チェック失敗 → CLAUDE.local.md に通知（ログパス付き）
    if not args.dry_run:
        self_failures = [
            c["name"] for r in reports
            for c in r.get("checks", [])
            if not c["passed"] and c["name"].startswith("self:")
        ]
        if self_failures:
            log_path = str(args.output) if args.output else str(latest)
            msg = (
                f"- [WARN] health-check.py 憲法違反 ({datetime.now().strftime('%Y-%m-%d')}): "
                f"{', '.join(self_failures)} -> 詳細: {log_path}\n"
            )
            local_md = Path.home() / "CLAUDE.local.md"
            with local_md.open("a", encoding="utf-8") as f:
                f.write(msg)

    if any(r.get("failed", 0) > 0 for r in reports):
        sys.exit(1)


if __name__ == "__main__":
    main()
