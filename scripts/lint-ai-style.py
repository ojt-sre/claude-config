#!/usr/bin/env python3
"""lint-ai-style.py — AI臭い表現のスコアリング（L4 Validation）

Markdown記事をスキャンし、AI生成っぽい表現パターンを検出・スコアリングする。
writer.md / reviewer.md / translator.md の禁止パターンを正規表現で実装。

使い方:
  python3 lint-ai-style.py article.md              # テキスト出力
  python3 lint-ai-style.py article.md --format json # JSON出力（パイプライン向け）
  python3 lint-ai-style.py article.md --threshold 70 && echo "PASS"  # 閾値チェック（超過でexit 1）
  python3 lint-ai-style.py --lang en article.md     # 英語記事モード
"""

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# --- 禁止パターン定義 ---
# weight: スコアへの加算値。重いほどAI臭い

@dataclass
class Pattern:
    name: str
    regex: str
    weight: int
    suggestion: str = ""

# 日本語パターン（writer.md + reviewer.md 由来）
JA_PATTERNS = [
    # AI定番の書き出し
    Pattern("注目されています", r"近年[、,].{0,20}(注目|重要性|必要性).{0,10}(されて|が高まって|増して)", 15,
            "具体的な体験から書き出す"),
    Pattern("重要性が高まっています", r"(重要性|必要性)が(高まって|増して)", 12,
            "具体的な体験から書き出す"),
    # 冗長な前置き
    Pattern("本記事では解説します", r"本(記事|稿)では.{0,20}(解説|紹介|説明)します", 15,
            "前置きを削って本題から始める"),
    # まとめの定番
    Pattern("いかがでしたでしょうか", r"いかがでし(た|ょうか)", 20,
            "学びと次のアクションで締める"),
    # 冗長表現
    Pattern("することができます", r"することができ(ます|る)", 8,
            "「〜できます」「〜できる」に短縮"),
    # 説教口調
    Pattern("注意が必要です", r"(という点に|には)注意が必要です", 8,
            "具体的に何が起きるかを書く"),
    Pattern("留意してください", r"に留意してください", 8,
            "具体的に何が起きるかを書く"),
    # 抽象的な強調（3回以上で加点）
    Pattern("非常に/とても/大変の多用", r"(非常に|とても|大変)", 3,
            "具体的な数字・事例に置き換える"),
    # 機械的な列挙
    Pattern("まず〜次に〜最後に", r"まず.{5,50}次に.{5,50}最後に", 10,
            "段落で流れを作る"),
    # 受動態の連続
    Pattern("推奨されます", r"(推奨|期待|想定)されます", 8,
            "「〜と思っている」「〜がいい」に書き換え"),
    # 空虚な導入
    Pattern("について解説", r"について(解説|紹介|説明)(し|いた)", 5,
            "前置きを削る"),
    # 箇条書きの過剰使用はパターンマッチで検出（後述の構造チェック）
]

# 英語パターン（translator.md + reviewer.md 由来）
EN_PATTERNS = [
    Pattern("In this article", r"[Ii]n this (article|post|guide),?\s+we\s+will", 15,
            "Start with a specific situation or problem"),
    Pattern("It's worth noting", r"[Ii]t'?s worth (noting|mentioning)", 12,
            "State the fact directly"),
    Pattern("It is important", r"[Ii]t is important to (note|mention|understand)", 12,
            "State the fact directly"),
    Pattern("Leveraging the power", r"[Ll]everag(e|ing) the (power|capabilities)", 10,
            "Use 'using' instead"),
    Pattern("robust/seamless/cutting-edge", r"\b(robust|seamless|cutting-edge|powerful|comprehensive)\b", 5,
            "Remove or replace with specific descriptions"),
    Pattern("In conclusion", r"\b[Ii]n conclusion,?", 12,
            "End with a concrete takeaway"),
    Pattern("To summarize", r"\b[Tt]o summarize,?", 10,
            "End with a concrete takeaway"),
    Pattern("utilizing", r"\b[Uu]tiliz(e|ing|ed)\b", 5,
            "Use 'using' or 'use' instead"),
    Pattern("it can be seen", r"[Ii]t can be (seen|observed|noted) that", 10,
            "State directly without hedging"),
    Pattern("it should be noted", r"[Ii]t should be (noted|mentioned) that", 10,
            "State directly"),
]


@dataclass
class Finding:
    line_num: int
    line_text: str
    pattern_name: str
    weight: int
    suggestion: str


def strip_frontmatter(text: str) -> str:
    """Markdownのfrontmatter（---で囲まれた部分）を除去。"""
    if text.startswith("---"):
        end = text.find("---", 3)
        if end != -1:
            return text[end + 3:]
    return text


def strip_code_blocks(text: str) -> str:
    """コードブロック内はチェック対象外。"""
    return re.sub(r"```[\s\S]*?```", "", text)


def count_consecutive_lists(text: str) -> int:
    """連続する箇条書きブロック数を数える。"""
    blocks = 0
    in_list = False
    consecutive = 0
    for line in text.split("\n"):
        is_list = bool(re.match(r"^\s*[-*]\s", line))
        if is_list and not in_list:
            consecutive += 1
            in_list = True
        elif not is_list and line.strip():
            if consecutive >= 3:
                blocks += 1
            in_list = False
            consecutive = 0 if not is_list else consecutive
    return blocks


def lint(text: str, lang: str = "ja") -> tuple[int, list[Finding]]:
    """テキストをスキャンしてスコアとfindingsを返す。"""
    clean = strip_code_blocks(strip_frontmatter(text))
    lines = clean.split("\n")
    patterns = JA_PATTERNS if lang == "ja" else EN_PATTERNS
    findings: list[Finding] = []

    for i, line in enumerate(lines, 1):
        for p in patterns:
            if re.search(p.regex, line):
                findings.append(Finding(
                    line_num=i,
                    line_text=line.strip()[:80],
                    pattern_name=p.name,
                    weight=p.weight,
                    suggestion=p.suggestion,
                ))

    # 構造チェック: 箇条書き3ブロック以上連続
    list_blocks = count_consecutive_lists(clean)
    if list_blocks > 0:
        findings.append(Finding(
            line_num=0, line_text=f"（箇条書き連続ブロック: {list_blocks}箇所）",
            pattern_name="箇条書きの過剰使用", weight=8 * list_blocks,
            suggestion="文章で流れを作る",
        ))

    score = min(100, sum(f.weight for f in findings))
    return score, findings


def format_text(score: int, findings: list[Finding], path: str, threshold: int) -> str:
    """テキスト出力。"""
    status = "FAIL" if score >= threshold else "PASS"
    lines = [f"[{status}] AI臭スコア: {score}/100 — {path}"]
    if findings:
        lines.append("")
        for f in findings:
            loc = f"L{f.line_num}" if f.line_num else "構造"
            lines.append(f"  [{loc}] {f.pattern_name} (+{f.weight})")
            if f.line_text:
                lines.append(f"    > {f.line_text}")
            if f.suggestion:
                lines.append(f"    → {f.suggestion}")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="AI臭い表現のスコアリング")
    parser.add_argument("file", help="対象のMarkdownファイル")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    parser.add_argument("--lang", choices=["ja", "en"], default="ja",
                        help="言語モード（デフォルト: ja）")
    parser.add_argument("--threshold", type=int, default=70,
                        help="C判定の閾値（デフォルト: 70）。超過で exit 1")
    args = parser.parse_args()

    path = Path(args.file)
    if not path.exists():
        print(f"ERROR: ファイルが見つかりません: {path}", file=sys.stderr)
        sys.exit(2)

    text = path.read_text(encoding="utf-8")
    score, findings = lint(text, lang=args.lang)

    if args.format == "json":
        result = {
            "file": str(path),
            "score": score,
            "threshold": args.threshold,
            "pass": score < args.threshold,
            "findings": [
                {"line": f.line_num, "pattern": f.pattern_name,
                 "weight": f.weight, "suggestion": f.suggestion,
                 "text": f.line_text}
                for f in findings
            ],
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(format_text(score, findings, str(path), args.threshold))

    if score >= args.threshold:
        sys.exit(1)


if __name__ == "__main__":
    main()
